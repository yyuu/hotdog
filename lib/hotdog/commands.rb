#!/usr/bin/env ruby

require "fileutils"
require "dogapi"
require "json"
require "sqlite3"

module Hotdog
  module Commands
    class BaseCommand
      PERSISTENT_DB = "persistent.db"
      MASK_DATABASE = 0xffff0000
      MASK_QUERY = 0x0000ffff

      def initialize(application)
        @application = application
        @logger = application.options[:logger]
        @options = application.options
        @dog = Dogapi::Client.new(options[:api_key], options[:application_key])
        @prepared_statements = {}
      end
      attr_reader :application
      attr_reader :logger
      attr_reader :options

      def run(args=[])
        raise(NotImplementedError)
      end

      def execute(query, args=[])
        update_db
        q = query.strip
        if 0 < args.length
          q += " -- VALUES (#{args.map { |arg| Array === arg ? "(#{arg.join(", ")})" : arg.inspect }.join(", ")})"
        end
        logger.debug(q)
        prepare(@db, query).execute(args)
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

      private
      def prepare(db, query)
        k = (db.hash & MASK_DATABASE) | (query.hash & MASK_QUERY)
        @prepared_statements[k] ||= db.prepare(query)
      end

      def format(result, options={})
        @options[:formatter].format(result, @options.merge(options))
      end

      def optparse()
        @application.optparse
      end

      def glob?(s)
        s.index('*') or s.index('?') or s.index('[') or s.index(']')
      end

      def host?(host_id)
        host_id = execute("SELECT id FROM hosts WHERE name = %s LIMIT 1", [s])
        not host_id.nil?
      end

      def get_hosts(hosts, tags=nil)
        tags ||= @options[:tags]
        update_db
        if 0 < tags.length
          result = hosts.map { |host_id|
            tags.map { |tag|
              tag_name, tag_value = tag.split(":", 2)
              case tag_name
              when "host"
                select_name_from_hosts_by_id(@db, host_id)
              else
                if glob?(tag_name)
                  select_tag_values_from_hosts_tags_by_host_id_and_tag_name_glob(@db, host_id, tag_name)
                else
                  select_tag_values_from_hosts_tags_by_host_id_and_tag_name(@db, host_id, tag_name)
                end
              end
            }
          }
          fields = tags
        else
          if @options[:listing]
            # TODO: should respect `:primary_tag`
            fields = []
            if hosts.empty?
              hosts = []
            else
              hosts = execute("SELECT id, name FROM hosts WHERE id IN (%s)" % hosts.map { "?" }.join(", "), hosts)
            end
            result = hosts.map { |host_id, host_name|
              tag_names = select_tag_names_from_hosts_tags_by_host_id(@db, host_id)
              tag_names.each do |tag_name|
                fields << tag_name unless fields.index(tag_name)
              end
              [host_name] + fields.map { |tag_name|
                if glob?(tag_name)
                  select_tag_values_from_hosts_tags_by_host_id_and_tag_name_glob(@db, host_id, tag_name)
                else
                  select_tag_values_from_hosts_tags_by_host_id_and_tag_name(@db, host_id, tag_name)
                end
              }
            }
            fields = ["host"] + fields
          else
            if @options[:primary_tag]
              fields = [@options[:primary_tag]]
              tag_name, tag_value = @options[:primary_tag].split(":", 2)
              case tag_name
              when "host"
                if hosts.empty?
                  result = []
                else
                  result = execute("SELECT name FROM hosts WHERE id IN (%s)" % hosts.map { "?" }.join(", "), hosts)
                end
              else
                result = hosts.map { |host_id|
                  if glob?(tag_name)
                    [select_tag_values_from_hosts_tags_by_host_id_and_tag_name_glob(@db, host_id, tag_name)]
                  else
                    [select_tag_values_from_hosts_tags_by_host_id_and_tag_name(@db, host_id, tag_name)]
                  end
                }
              end
            else
              fields = ["host"]
              if hosts.empty?
                result = []
              else
                result = execute("SELECT name FROM hosts WHERE id IN (%s)" % hosts.map { "?" }.join(", "), hosts)
              end
            end
          end
        end
        [result, fields]
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

          if not options[:force] and File.exist?(persistent) and Time.new < File.mtime(persistent) + options[:expiry]
            begin
              persistent_db = SQLite3::Database.new(persistent)
              persistent_db.execute("SELECT id, name FROM hosts LIMIT 1")
              persistent_db.execute("SELECT id, name, value FROM tags LIMIT 1")
              persistent_db.execute("SELECT host_id, tag_id FROM hosts_tags LIMIT 1")
              @db = persistent_db
              return
            rescue SQLite3::SQLException
              persistent_db.close()
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

          known_tags = all_tags.keys.map { |tag| split_tag(tag) }.uniq
          prepare(memory_db, <<-EOS % known_tags.map { "(?, ?)" }.join(", ")).execute(known_tags) unless known_tags.empty?
            INSERT OR IGNORE INTO tags (name, value) VALUES %s;
          EOS

          known_hosts = all_tags.values.reduce(:+).uniq
          prepare(memory_db, <<-EOS % known_hosts.map { "(?)" }.join(", ")).execute(known_hosts) unless known_hosts.empty?
            INSERT OR IGNORE INTO hosts (name) VALUES %s;
          EOS

          all_tags.each do |tag, hosts|
            tag_name, tag_value = split_tag(tag)
            prepare(memory_db, <<-EOS % hosts.map { "?" }.join(", ")).execute(hosts + [tag_name, tag_value]) unless hosts.empty?
              INSERT OR REPLACE INTO hosts_tags (host_id, tag_id)
                SELECT host.id, tag.id FROM
                  ( SELECT id FROM hosts WHERE name IN (%s) ) AS host,
                  ( SELECT id FROM tags WHERE name = ? AND value = ? LIMIT 1 ) AS tag;
            EOS
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
        code, all_tags = @dog.all_tags()
        logger.debug("dog.all_tags() #==> [%s, ...]" % [code.inspect])
        if code.to_i / 100 != 2
          raise("dog.all_tags() returns [%s, ...]" % [code.inspect])
        end
        code, all_downtimes = @dog.get_all_downtimes()
        logger.debug("dog.get_all_downtimes() #==> [%s, ...]" % [code.inspect])
        if code.to_i / 100 != 2
          raise("dog.get_all_downtimes() returns [%s, ...]" % [code.inspect])
        end
        now = Time.new.to_i
        downtimes = all_downtimes.select { |downtime|
          # active downtimes
          downtime["active"] and ( downtime["start"].nil? or downtime["start"] < now ) and ( downtime["end"].nil? or now <= downtime["end"] )
        }.map { |downtime|
          # find host scopes
          downtime["scope"].select { |scope| scope.start_with?("host:") }.map { |scope| scope.sub(/\Ahost:/, "") }
        }.reduce(:+) || []
        if not downtimes.empty?
          logger.info("ignore host(s) with scheduled downtimes: #{downtimes.inspect}")
        end
        Hash[all_tags["tags"].map { |tag, hosts| [tag, hosts.reject { |host| downtimes.include?(host) }] }]
      end

      def split_tag(tag)
        tag_name, tag_value = tag.split(":", 2)
        [tag_name, tag_value || ""]
      end

      def copy_db(src, dst)
        # create index later for better insert performance
        dst.transaction do
          create_table_hosts(dst)
          create_table_tags(dst)
          create_table_hosts_tags(dst)

          hosts = prepare(src, "SELECT id, name FROM hosts").execute().to_a
          prepare(dst, <<-EOS % hosts.map { "(?, ?)" }.join(", ")).execute(hosts) unless hosts.empty?
            INSERT INTO hosts (id, name) VALUES %s;
          EOS

          tags = prepare(src, "SELECT id, name, value FROM tags").execute().to_a
          prepare(dst, <<-EOS % tags.map { "(?, ?, ?)" }.join(", ")).execute(tags) unless tags.empty?
            INSERT INTO tags (id, name, value) VALUES %s;
          EOS

          hosts_tags = prepare(src, "SELECT host_id, tag_id FROM hosts_tags").to_a
          prepare(dst, <<-EOS % hosts_tags.map { "(?, ?)" }.join(", ")).execute(hosts_tags) unless hosts_tags.empty?
            INSERT INTO hosts_tags (host_id, tag_id) VALUES %s;
          EOS

          create_index_hosts(dst)
          create_index_tags(dst)
          create_index_hosts_tags(dst)
        end
      end

      def create_table_hosts(db)
        logger.debug("create_table_hosts()")
        db.execute(<<-EOS)
          CREATE TABLE IF NOT EXISTS hosts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(255) NOT NULL COLLATE NOCASE
          );
        EOS
      end

      def create_index_hosts(db)
        logger.debug("create_index_hosts()")
        db.execute("CREATE UNIQUE INDEX IF NOT EXISTS hosts_name ON hosts ( name )")
      end

      def create_table_tags(db)
        logger.debug("create_table_tags()")
        db.execute(<<-EOS)
          CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(200) NOT NULL COLLATE NOCASE,
            value VARCHAR(200) NOT NULL COLLATE NOCASE DEFAULT ""
          );
        EOS
      end

      def create_index_tags(db)
        logger.debug("create_index_tags()")
        db.execute("CREATE UNIQUE INDEX IF NOT EXISTS tags_name_value ON tags ( name, value )")
      end

      def create_table_hosts_tags(db)
        logger.debug("create_table_hosts_tags()")
        db.execute(<<-EOS)
          CREATE TABLE IF NOT EXISTS hosts_tags (
            host_id INTEGER NOT NULL,
            tag_id INTEGER NOT NULL
          );
        EOS
      end

      def create_index_hosts_tags(db)
        logger.debug("create_index_hosts_tags()")
        db.execute("CREATE UNIQUE INDEX IF NOT EXISTS hosts_tags_host_id_tag_id ON hosts_tags ( host_id, tag_id )")
      end

      def select_name_from_hosts_by_id(db, host_id)
        logger.debug("select_name_from_hosts_by_id(%s)" % [host_id.inspect])
        prepare(db, "SELECT name FROM hosts WHERE id = ? LIMIT 1").execute(host_id).map { |row| row.first }.first
      end

      def select_tag_values_from_hosts_tags_by_host_id_and_tag_name_glob(db, host_id, tag_name)
        logger.debug("select_tag_values_from_hosts_tags_by_host_id_and_tag_name_glob(%s, %s)" % [host_id.inspect, tag_name.inspect])
        prepare(db, <<-EOS).execute(host_id, tag_name).map { |row| row.first }.join(",")
          SELECT tags.value FROM hosts_tags
            INNER JOIN tags ON hosts_tags.tag_id = tags.id
              WHERE hosts_tags.host_id = ? AND tags.name GLOB ?;
        EOS
      end

      def select_tag_values_from_hosts_tags_by_host_id_and_tag_name(db, host_id, tag_name)
        logger.debug("select_tag_values_from_hosts_tags_by_host_id_and_tag_name(%s, %s)" % [host_id.inspect, tag_name.inspect])
        prepare(db, <<-EOS).execute(host_id, tag_name).map { |row| row.first }.join(",")
          SELECT tags.value FROM hosts_tags
            INNER JOIN tags ON hosts_tags.tag_id = tags.id
              WHERE hosts_tags.host_id = ? AND tags.name = ?;
        EOS
      end

      def select_tag_names_from_hosts_tags_by_host_id(db, host_id)
        logger.debug("select_tag_names_from_hosts_tags_by_host_id(%s)" % [host_id.inspect])
        prepare(db, <<-EOS).execute(host_id).map { |row| row.first }
          SELECT DISTINCT tags.name FROM hosts_tags
            INNER JOIN tags ON hosts_tags.tag_id = tags.id
              WHERE hosts_tags.host_id = ?;
        EOS
      end
    end
  end
end

# vim:set ft=ruby :
