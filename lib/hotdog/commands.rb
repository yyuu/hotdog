#!/usr/bin/env ruby

require "fileutils"
require "dogapi"
require "multi_json"
require "oj"
require "open-uri"
require "parallel"
require "sqlite3"
require "uri"

module Hotdog
  module Commands
    SQLITE_LIMIT_COMPOUND_SELECT = 500 # TODO: get actual value from `sqlite3_limit()`?

    class BaseCommand
      PERSISTENT_DB = "persistent.db"
      MASK_DATABASE = 0xffff0000
      MASK_QUERY = 0x0000ffff

      def initialize(application)
        @application = application
        @logger = application.options[:logger]
        @options = application.options
        @dog = nil # lazy initialization
        @prepared_statements = {}
      end
      attr_reader :application
      attr_reader :logger
      attr_reader :options

      def run(args=[], options={})
        raise(NotImplementedError)
      end

      def execute(q, args=[])
        update_db
        begin
          logger.debug("execute: #{q} -- #{args.inspect}")
          prepare(@db, q).execute(args)
        rescue
          logger.error("failed: #{q} -- #{args.inspect}")
          raise
        end
      end

      def fixed_string?()
        @options[:fixed_string]
      end

      def reload(options={})
        if @db
          close_db(@db)
          @db = nil
        end
        update_db(options)
      end

      def define_options(optparse, options={})
        # nop
      end

      def parse_options(optparse, args=[])
        optparse.parse(args)
      end

      private
      def prepare(db, query)
        k = (db.hash & MASK_DATABASE) | (query.hash & MASK_QUERY)
        @prepared_statements[k] ||= db.prepare(query)
      end

      def format(result, options={})
        @options[:formatter].format(result, @options.merge(options))
      end

      def glob?(s)
        s.index('*') or s.index('?') or s.index('[') or s.index(']')
      end

      def get_hosts(host_ids, tags=nil)
        tags ||= @options[:tags]
        update_db
        if host_ids.empty?
          [[], []]
        else
          if 0 < tags.length
            fields = tags.map { |tag|
              tag_name, tag_value = split_tag(tag)
              tag_name
            }
            get_hosts_fields(host_ids, fields)
          else
            if @options[:listing]
              q1 = "SELECT DISTINCT tags.name FROM hosts_tags " \
                     "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                       "WHERE hosts_tags.host_id IN (%s);"
              if @options[:primary_tag]
                fields = [
                  @options[:primary_tag],
                  "host",
                ] + host_ids.each_slice(SQLITE_LIMIT_COMPOUND_SELECT).flat_map { |host_ids|
                  execute(q1 % host_ids.map { "?" }.join(", "), host_ids).map { |row| row.first }.reject { |tag_name|
                    tag_name == @options[:primary_tag]
                  }
                }
                get_hosts_fields(host_ids, fields)
              else
                fields = [
                  "host",
                ] + host_ids.each_slice(SQLITE_LIMIT_COMPOUND_SELECT).flat_map { |host_ids|
                  execute(q1 % host_ids.map { "?" }.join(", "), host_ids).map { |row| row.first }
                }
                get_hosts_fields(host_ids, fields)
              end
            else
              if @options[:primary_tag]
                get_hosts_fields(host_ids, [@options[:primary_tag]])
              else
                get_hosts_fields(host_ids, ["host"])
              end
            end
          end
        end
      end

      def get_hosts_fields(host_ids, fields)
        if fields.empty?
          [[], fields]
        else
          fields_without_host = fields.reject { |tag_name| tag_name == "host" }
          if fields == fields_without_host
            host_names = {}
          else
            host_names = Hash[
              host_ids.each_slice(SQLITE_LIMIT_COMPOUND_SELECT).flat_map { |host_ids|
                execute("SELECT id, name FROM hosts WHERE id IN (%s)" % host_ids.map { "?" }.join(", "), host_ids).map { |row| row.to_a }
              }
            ]
          end
          q1 = "SELECT tags.name, GROUP_CONCAT(tags.value, ',') FROM hosts_tags " \
                 "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                   "WHERE hosts_tags.host_id = ? AND tags.name IN (%s) " \
                     "GROUP BY tags.name;"
          result = host_ids.map { |host_id|
            tag_values = Hash[
              fields_without_host.each_slice(SQLITE_LIMIT_COMPOUND_SELECT - 1).flat_map { |fields_without_host|
                execute(q1 % fields_without_host.map { "?" }.join(", "), [host_id] + fields_without_host).map { |row| row.to_a }
              }
            ]
            fields.map { |tag_name|
              if tag_name == "host"
                host_names.fetch(host_id, nil)
              else
                tag_value = tag_values.fetch(tag_name, nil)
                if tag_value
                  if tag_value.empty?
                    tag_name # use `tag_name` as `tag_value` for the tags without any values
                  else
                    tag_value
                  end
                else
                  nil
                end
              end
            }
          }
          [result, fields]
        end
      end

      def close_db(db, options={})
        @prepared_statements = @prepared_statements.reject { |k, statement|
          (db.hash & MASK_DATABASE == k & MASK_DATABASE).tap do |delete_p|
            statement.close() if delete_p
          end
        }
        db.close()
      end

      def update_db(options={})
        options = @options.merge(options)
        if @db.nil?
          FileUtils.mkdir_p(options[:confdir])
          persistent = File.join(options[:confdir], PERSISTENT_DB)

          if (not options[:force] and File.exist?(persistent) and Time.new < File.mtime(persistent) + options[:expiry]) or options[:offline]
            begin
              persistent_db = SQLite3::Database.new(persistent)
              persistent_db.execute("SELECT id, name FROM hosts LIMIT 1")
              persistent_db.execute("SELECT id, name, value FROM tags LIMIT 1")
              persistent_db.execute("SELECT host_id, tag_id FROM hosts_tags LIMIT 1")
              @db = persistent_db
              return
            rescue SQLite3::SQLException
              if options[:offline]
                raise(RuntimeError.new("no database available on offline mode"))
              else
                persistent_db.close()
              end
            end
          end

          memory_db = SQLite3::Database.new(":memory:")
          create_table_hosts(memory_db)
          create_index_hosts(memory_db)
          create_table_tags(memory_db)
          create_index_tags(memory_db)
          create_table_hosts_tags(memory_db)
          create_index_hosts_tags(memory_db)

          all_tags = get_all_tags()

          memory_db.transaction do
            known_tags = all_tags.keys.map { |tag| split_tag(tag) }.uniq
            known_tags.each_slice(SQLITE_LIMIT_COMPOUND_SELECT / 2) do |known_tags|
              q = "INSERT OR IGNORE INTO tags (name, value) VALUES %s" % known_tags.map { "(?, ?)" }.join(", ")
              begin
                logger.debug("execute: #{q} -- #{known_tags.inspect}")
                prepare(memory_db, q).execute(known_tags)
              rescue
                logger.error("failed: #{q} -- #{known_tags.inspect}")
                raise
              end
            end

            known_hosts = all_tags.values.reduce(:+).uniq
            known_hosts.each_slice(SQLITE_LIMIT_COMPOUND_SELECT) do |known_hosts|
              q = "INSERT OR IGNORE INTO hosts (name) VALUES %s" % known_hosts.map { "(?)" }.join(", ")
              begin
                logger.debug("execute: #{q} -- #{known_hosts.inspect}")
                prepare(memory_db, q).execute(known_hosts)
              rescue
                logger.error("failed: #{q} -- #{known_hosts.inspect}")
                raise
              end
            end

            all_tags.each do |tag, hosts|
              hosts.each_slice(SQLITE_LIMIT_COMPOUND_SELECT - 2) do |hosts|
                q = "INSERT OR REPLACE INTO hosts_tags (host_id, tag_id) " \
                      "SELECT host.id, tag.id FROM " \
                        "( SELECT id FROM hosts WHERE name IN (%s) ) AS host, " \
                        "( SELECT id FROM tags WHERE name = ? AND value = ? LIMIT 1 ) AS tag;" % hosts.map { "?" }.join(", ")
                hosts_tag = hosts + split_tag(tag)
                begin
                  logger.debug("execute: #{q} -- #{hosts_tag.inspect}")
                  prepare(memory_db, q).execute(hosts_tag)
                rescue
                  logger.error("failed: #{q} -- #{hosts_tag.inspect}")
                  raise
                end
              end
            end
          end

          # backup in-memory db to file
          FileUtils.rm_f(persistent)
          persistent_db = SQLite3::Database.new(persistent)
          copy_db(memory_db, persistent_db)
          close_db(persistent_db)
          @db = memory_db
        else
          @db
        end
      end

      def get_all_tags() #==> Hash<Tag,Array<Host>>
        endpoint = ENV.fetch("DATADOG_HOST", "https://app.datadoghq.com")
        requests = {all_downtime: "/api/v1/downtime", all_tags: "/api/v1/tags/hosts"}
        query = URI.encode_www_form(api_key: options[:api_key], application_key: options[:application_key])
        begin
          responses = Hash[Parallel.map(requests) { |name, request_path|
            uri = URI.join(endpoint, "#{request_path}?#{query}")
            begin
              response = uri.open { |fp| fp.read }
              [name, MultiJson.load(response)]
            rescue OpenURI::HTTPError => error
              code, body = error.io.status
              raise(RuntimeError.new("dog.get_#{name}() returns [#{code.inspect}, ...]"))
            end
          }]
        rescue => error
          STDERR.puts(error.message)
          exit(1)
        end
        now = Time.new.to_i
        downtimes = responses.fetch(:all_downtime, []).select { |downtime|
          # active downtimes
          downtime["active"] and ( downtime["start"].nil? or downtime["start"] < now ) and ( downtime["end"].nil? or now <= downtime["end"] )
        }.flat_map { |downtime|
          # find host scopes
          downtime["scope"].select { |scope| scope.start_with?("host:") }.map { |scope| scope.sub(/\Ahost:/, "") }
        }
        if not downtimes.empty?
          logger.info("ignore host(s) with scheduled downtimes: #{downtimes.inspect}")
        end
        Hash[responses.fetch(:all_tags, {}).fetch("tags", []).map { |tag, hosts| [tag, hosts.reject { |host| downtimes.include?(host) }] }]
      end

      def dog()
        @dog ||= Dogapi::Client.new(options[:api_key], options[:application_key])
      end

      def split_tag(tag)
        tag_name, tag_value = tag.split(":", 2)
        [tag_name, tag_value || ""]
      end

      def join_tag(tag_name, tag_value)
        if tag_value.to_s.empty?
          tag_name
        else
          "#{tag_name}:#{tag_value}"
        end
      end

      def copy_db(src, dst)
        # create index later for better insert performance
        dst.transaction do
          create_table_hosts(dst)
          create_table_tags(dst)
          create_table_hosts_tags(dst)

          hosts = prepare(src, "SELECT id, name FROM hosts").execute().to_a
          hosts.each_slice(SQLITE_LIMIT_COMPOUND_SELECT / 2) do |hosts|
            q = "INSERT INTO hosts (id, name) VALUES %s" % hosts.map { "(?, ?)" }.join(", ")
            begin
              logger.debug("execute: #{q} -- #{hosts.inspect}")
              prepare(dst, q).execute(hosts)
            rescue
              logger.error("failed: #{q} -- #{hosts.inspect}")
              raise
            end
          end

          tags = prepare(src, "SELECT id, name, value FROM tags").execute().to_a
          tags.each_slice(SQLITE_LIMIT_COMPOUND_SELECT / 3) do |tags|
            q = "INSERT INTO tags (id, name, value) VALUES %s" % tags.map { "(?, ?, ?)" }.join(", ")
            begin
              logger.debug("execute: #{q} -- #{tags.inspect}")
              prepare(dst, q).execute(tags)
            rescue
              logger.error("failed: #{q} -- #{tags.inspect}")
              raise
            end
          end

          hosts_tags = prepare(src, "SELECT host_id, tag_id FROM hosts_tags").to_a
          hosts_tags.each_slice(SQLITE_LIMIT_COMPOUND_SELECT / 2) do |hosts_tags|
            q = "INSERT INTO hosts_tags (host_id, tag_id) VALUES %s" % hosts_tags.map { "(?, ?)" }.join(", ")
            begin
              logger.debug("execute: #{q} -- #{hosts_tags.inspect}")
              prepare(dst, q).execute(hosts_tags)
            rescue
              logger.error("failed: #{q} -- #{hosts_tags.inspect}")
              raise
            end
          end

          create_index_hosts(dst)
          create_index_tags(dst)
          create_index_hosts_tags(dst)
        end
      end

      def create_table_hosts(db)
        q = "CREATE TABLE IF NOT EXISTS hosts ( " \
              "id INTEGER PRIMARY KEY AUTOINCREMENT, " \
              "name VARCHAR(255) NOT NULL COLLATE NOCASE " \
            ");"
        logger.debug(q)
        db.execute(q)
      end

      def create_index_hosts(db)
        q = "CREATE UNIQUE INDEX IF NOT EXISTS hosts_name ON hosts ( name );"
        logger.debug(q)
        db.execute(q)
      end

      def create_table_tags(db)
        q = "CREATE TABLE IF NOT EXISTS tags ( " \
              "id INTEGER PRIMARY KEY AUTOINCREMENT, " \
              "name VARCHAR(200) NOT NULL COLLATE NOCASE, " \
              "value VARCHAR(200) NOT NULL COLLATE NOCASE " \
            ");"
        logger.debug(q)
        db.execute(q)
      end

      def create_index_tags(db)
        q = "CREATE UNIQUE INDEX IF NOT EXISTS tags_name_value ON tags ( name, value );"
        logger.debug(q)
        db.execute(q)
      end

      def create_table_hosts_tags(db)
        q = "CREATE TABLE IF NOT EXISTS hosts_tags ( " \
              "host_id INTEGER NOT NULL, " \
              "tag_id INTEGER NOT NULL " \
            ");"
        logger.debug(q)
        db.execute(q)
      end

      def create_index_hosts_tags(db)
        q = "CREATE UNIQUE INDEX IF NOT EXISTS hosts_tags_host_id_tag_id ON hosts_tags ( host_id, tag_id );"
        logger.debug(q)
        db.execute(q)
      end
    end
  end
end

# vim:set ft=ruby :
