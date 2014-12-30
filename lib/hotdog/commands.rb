#!/usr/bin/env ruby

require "dogapi"
require "logger"

module Hotdog
  module Commands
    class BaseCommand
      def initialize(db, options={})
        @db = db
        @formatter = options[:formatter]
        @logger = options[:logger]
        @tags = options[:tags]
        @application = options[:application]
        @options = options
        @dog = Dogapi::Client.new(options[:api_key], options[:application_key])
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

      private
      def format(result, options={})
        @formatter.format(result, @options.merge(options))
      end

      def get_hosts(hosts=[])
        if 0 < tags.length
          result = hosts.map { |host_id|
            update_host_tags(host_id, @options.merge(tags: tags))
            tags.map { |tag|
              tag_name, tag_value = tag.split(":", 2)
              if tag_name == "host"
                logger.debug("get_hosts_q1()")
                @get_hosts_q1 ||= @db.prepare(<<-EOS)
                  SELECT name FROM hosts WHERE id = ? LIMIT 1;
                EOS
                @get_hosts_q1.execute(host_id).map { |row| row.first }.join(",")
              else
                logger.debug("get_hosts_q2()")
                @get_hosts_q2 ||= @db.prepare(<<-EOS)
                  SELECT tags.value FROM hosts_tags
                    INNER JOIN tags ON hosts_tags.tag_id = tags.id
                      WHERE hosts_tags.host_id = ? AND tags.name = ?;
                EOS
                @get_hosts_q2.execute(host_id, tag_name).map { |row| row.first }.join(",")
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
              update_host_tags(host_name, @options.dup)
              logger.debug("get_hosts_q3()")
              @get_hosts_q3 ||= @db.prepare(<<-EOS)
                SELECT DISTINCT tags.name FROM hosts_tags
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE hosts_tags.host_id = ?;
              EOS
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

      def update_hosts(options={})
        @db.transaction do
          if not options[:force]
            @update_hosts_q1 ||= @db.prepare("SELECT MIN(expires_at) FROM hosts_tags;")
            logger.debug("update_hosts_q1()")
            if expires_at = @update_hosts_q1.execute().map { |row| row.first }.first
              if Time.new.to_i < expires_at
                return
              else
                logger.debug("minimum expires_at was %s. start updateing." % [Time.at(expires_at)])
              end
            else
              logger.debug("expires_at not found. start updateing.")
            end
          end

          code, result = @dog.search("hosts:")
          if code.to_i / 100 != 2
            raise("HTTP #{code}: #{result.inspect}")
          end

          result["results"]["hosts"].each do |host_name|
            @update_hosts_q2 ||= @db.prepare("INSERT OR IGNORE INTO hosts (name) VALUES (?);")
            logger.debug("update_hosts_q2(%s)" % [host_name.inspect])
            @update_hosts_q2.execute(host_name)
            update_host_tags(host_name, options)
          end

          execute(<<-EOS % result["results"]["hosts"].map { "LOWER(?)" }.join(", "), result["results"]["hosts"])
            DELETE FROM hosts_tags WHERE host_id NOT IN
              ( SELECT id FROM hosts WHERE LOWER(name) IN ( %s ) );
          EOS
        end
      end

      def update_tags(options={})
        @db.transaction do
          if options[:force]
            @update_tags_q1 ||= @db.prepare(<<-EOS)
              SELECT DISTINCT hosts_tags.host_id FROM hosts_tags;
            EOS
            logger.debug("update_tags_q1()")
            hosts = @update_tags_q1.execute().map { |row| row.first }
          else
            logger.debug("update_tags_q2()")
            @update_tags_q2 ||= @db.prepare(<<-EOS)
              SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                WHERE hosts_tags.expires_at < ?;
            EOS
            hosts = @update_tags_q2.execute(Time.new.to_i)
          end
          hosts.each do |host_name|
            update_host_tags(host_name, options)
          end
        end
      end

      def update_host_tags(host_name, options={})
        if Integer === host_name
          host_id = host_name
          @update_host_tags_q1 ||= @db.prepare("SELECT name FROM hosts WHERE id = ? LIMIT 1;")
          logger.debug("update_host_tags_q1(%s)" % [host_id.inspect])
          host_name = @update_host_tags_q1.execute(host_id).map { |row| row.first }.first
        else
          @update_host_tags_q2 ||= @db.prepare("SELECT id FROM hosts WHERE LOWER(name) = LOWER(?) LIMIT 1;")
          logger.debug("update_host_tags_q2(%s)" % [host_name.inspect])
          host_id = @update_host_tags_q2.execute(host_name).map { |row| row.first }.first
        end

        if not options[:force]
          @update_host_tags_q3 ||= @db.prepare("SELECT MIN(expires_at) FROM hosts_tags WHERE host_id = ?;")
          logger.debug("update_host_tags_q3(%s)" % [host_id.inspect])
          if expires_at = @update_host_tags_q3.execute(host_id).map { |row| row.first }.first
            if Time.new.to_i < expires_at
              return
            else
              logger.debug("%s: minimum expires_at was %s. start updating." % [host_name, Time.at(expires_at)])
            end
          else
            logger.debug("%s: expires_at not found. start updateing." % [host_name])
          end
        end

        code, result = @dog.host_tags(host_name)
        if code.to_i / 100 != 2
          case code.to_i
          when 404 # host not found on datadog
            @update_host_tags_q7 ||= @db.prepare("DELETE FROM hosts_tags WHERE host_id IN ( SELECT id FROM hosts WHERE LOWER(name) = LOWER(?) );")
            @update_host_tags_q7.execute(host_name)
          end
          raise("HTTP #{code}: #{result.inspect}")
        end

        expires_at = Time.new.to_i + (options[:minimum_expiry] + rand(options[:random_expiry]))
        logger.debug("%s: expires_at=%s" % [host_name, Time.at(expires_at)])

        result["tags"].each do |tag|
          tag_name, tag_value = tag.split(":", 2)
          tag_value ||= ""

          if options.has_key?(:tags) and not options[:tags].empty? and not options[:tags].index(tag_name)
            next
          else
            @update_host_tags_q4 ||= @db.prepare("INSERT OR IGNORE INTO tags (name, value) VALUES (?, ?);")
            logger.debug("update_host_tags_q4(%s, %s)" % [tag_name.inspect, tag_value.inspect])
            @update_host_tags_q4.execute(tag_name, tag_value)
            @update_host_tags_q5 ||= @db.prepare(<<-EOS)
              INSERT OR REPLACE INTO hosts_tags (host_id, tag_id, expires_at)
                SELECT host.id, tag.id, ? FROM
                  ( SELECT id FROM hosts WHERE name = ? ) AS host,
                  ( SELECT id FROM tags WHERE name = ? AND value = ? ) AS tag;
            EOS
            logger.debug("update_host_tags_q5(%s, %s)" % [expires_at, host_name, tag_name, tag_value])
            @update_host_tags_q5.execute(expires_at, host_name, tag_name, tag_value)
          end
        end

        @update_host_tags_q6 ||= @db.prepare(<<-EOS)
          DELETE FROM hosts_tags WHERE host_id = ? and expires_at <= ?;
        EOS
        logger.debug("update_host_tags_q6(%s, %s)" % [host_id.inspect, Time.new.to_i.inspect])
        @update_host_tags_q6.execute(host_id, Time.new.to_i)
      end
    end
  end
end

# vim:set ft=ruby :
