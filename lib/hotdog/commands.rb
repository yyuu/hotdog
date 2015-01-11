#!/usr/bin/env ruby

require "dogapi"
require "logger"

module Hotdog
  module Commands
    class BaseCommand
      def initialize(db, options={})
        @db = db
        @fixed_string = options[:fixed_string]
        @formatter = options[:formatter]
        @logger = options[:logger]
        @tags = options[:tags]
        @application = options[:application]
        @options = options
        @dog = Dogapi::Client.new(options[:api_key], options[:application_key])
        @started_at = Time.new
        @suspended = false
      end
      attr_reader :application
      attr_reader :formatter
      attr_reader :logger
      attr_reader :tags
      attr_reader :options

      def run(args=[])
        raise(NotImplementedError)
      end

      def execute(query, *args)
        q = query.strip
        if 0 < args.length
          q += " -- VALUES (#{args.map { |arg| Array === arg ? "(#{arg.join(", ")})" : arg.inspect }.join(", ")})"
        end
        logger.debug(q)
        @db.execute(query, args)
      end

      def fixed_string?()
        @fixed_string
      end

      def suspended?()
        @suspended
      end

      private
      def format(result, options={})
        @formatter.format(result, @options.merge(options))
      end

      def glob?(s)
        s.index('*') or s.index('?') or s.index('[') or s.index(']')
      end

      def get_hosts(hosts=[])
        if 0 < tags.length
          result = hosts.map { |host_id|
            tags.map { |tag|
              tag_name, tag_value = tag.split(":", 2)
              case tag_name
              when "host"
                @get_hosts_q1 ||= @db.prepare(<<-EOS)
                  SELECT name FROM hosts WHERE id = ? LIMIT 1;
                EOS
                logger.debug("get_hosts_q1(%s)" % [host_id.inspect])
                @get_hosts_q1.execute(host_id).map { |row| row.first }.first
              else
                if not glob?(tag_name)
                  @get_hosts_q2 ||= @db.prepare(<<-EOS)
                    SELECT tags.value FROM hosts_tags
                      INNER JOIN tags ON hosts_tags.tag_id = tags.id
                        WHERE hosts_tags.host_id = ? AND tags.name = ?;
                  EOS
                  logger.debug("get_hosts_q2(%s, %s)" % [host_id.inspect, tag_name.inspect])
                  @get_hosts_q2.execute(host_id, tag_name).map { |row| row.first }.join(",")
                else
                  @get_hosts_q5 ||= @db.prepare(<<-EOS)
                    SELECT tags.value FROM hosts_tags
                      INNER JOIN tags ON hosts_tags.tag_id = tags.id
                        WHERE hosts_tags.host_id = ? AND tags.name GLOB ?;
                  EOS
                  logger.debug("get_hosts_q5(%s, %s)", host_id.inspect, tag_name.inspect)
                  @get_hosts_q5.execute(host_id, tag_name).map { |row| row.first }.join(",")
                end
              end
            }
          }
          fields = tags
        else
          if options[:listing]

            fields = []
            hosts = execute(<<-EOS % hosts.map { "?" }.join(", "), hosts)
              SELECT id, name FROM hosts WHERE id IN (%s) ORDER BY name;
            EOS
            result = hosts.map { |host_id, host_name|
              @get_hosts_q3 ||= @db.prepare(<<-EOS)
                SELECT DISTINCT tags.name FROM hosts_tags
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE hosts_tags.host_id = ?;
              EOS
              logger.debug("get_hosts_q3(%s)" % [host_id.inspect])
              tag_names = @get_hosts_q3.execute(host_id).map { |row| row.first }
              tag_names.each do |tag_name|
                fields << tag_name unless fields.index(tag_name)
              end
              [host_name] + fields.map { |tag_name|
                @get_hosts_q4 ||= @db.prepare(<<-EOS)
                  SELECT tags.value FROM hosts_tags
                    INNER JOIN tags ON hosts_tags.tag_id = tags.id
                      WHERE hosts_tags.host_id = ? AND tags.name = ?;
                EOS
                logger.debug("get_hosts_q4(%s, %s)" % [host_id.inspect, tag_name.inspect])
                @get_hosts_q4.execute(host_id, tag_name).map { |row| row.first }.join(",")
              }
            }
            fields = ["host"] + fields
          else
            fields = ["host"]
            result = execute(<<-EOS % hosts.map { "?" }.join(", "), hosts)
              SELECT name FROM hosts WHERE id IN (%s) ORDER BY name; 
            EOS
          end
        end
        [result, fields]
      end

      def init_tables(options={})
        execute(<<-EOS)
          CREATE TABLE IF NOT EXISTS hosts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(255) NOT NULL
          );
        EOS
        execute(<<-EOS)
          CREATE UNIQUE INDEX IF NOT EXISTS hosts_name ON hosts ( name );
        EOS
        execute(<<-EOS)
          CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(200) NOT NULL,
            value VARCHAR(200) NOT NULL DEFAULT ""
          );
        EOS
        execute(<<-EOS)
          CREATE UNIQUE INDEX IF NOT EXISTS tags_name_value ON tags ( name, value );
        EOS
        execute(<<-EOS)
          CREATE TABLE IF NOT EXISTS hosts_tags (
            host_id INTEGER NOT NULL,
            tag_id INTEGER NOT NULL
          );
        EOS
        execute(<<-EOS)
          CREATE UNIQUE INDEX IF NOT EXISTS hosts_tags_host_id_tag_id ON hosts_tags ( host_id, tag_id );
        EOS

        update_tables(options)
      end

      def update_tables(options={})
        code, result = @dog.all_tags()
        logger.debug("dog.all_tags() #==> [%s, ...]" % [code.inspect])
        if code.to_i / 100 != 2
          raise("dog.all_tags() returns (%s: ...)" % [code.inspect])
        end

        result["tags"] do |tag, hosts|
          tag_name, tag_value = tag.split(":", 2)
          tag_value ||= ""
          @insert_or_ignore_into_tags ||= @db.prepare("INSERT OR IGNORE INTO tags (name, value) VALUES (?, ?)")
          logger.debug("insert_or_ignore_into_tags(%s, %s)" % [tag_name.inspect, tag_value.inspect])
          @insert_or_ignore_into_tags.execute(tag_name, tag_value)

          hosts.each do |host_name|
            @insert_or_ignore_into_hosts ||= @db.prepare("INSERT OR IGNORE INTO hosts (name) VALUES (?)")
            logger.debug("insert_or_ignore_into_hosts(%s)" % [host_name.inspect])
            @insert_or_ignore_into_hosts.execute(host_name)

            @insert_or_replace_into_hosts_tags ||= @db.prepare(<<-EOS)
              INSERT OR REPLACE INTO hosts_tags (host_id, tag_id)
                SELECT host.id, tag.id, ? FROM
                  ( SELECT id FROM hosts WHERE name = ? ) AS host,
                  ( SELECT id FROM tags WHERE name = ? AND value = ? ) AS tag;
            EOS
            logger.debug("insert_or_replace_into_hosts_tags(%s, %s, %s)" % [host_name.inspect, tag_name.inspect, tag_value.inspect])
            @insert_or_replace_into_hosts_tags.execute(expies_at, host_name, tag_name, tag_value)
          end
        end
      end
    end
  end
end

# vim:set ft=ruby :
