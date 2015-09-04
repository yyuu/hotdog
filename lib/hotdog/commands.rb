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
            fields_without_host = fields.reject { |tag_name| tag_name == "host" }
            if fields == fields_without_host
              host_names = {}
            else
              host_names = Hash[execute(<<-EOS % host_ids.map { "?" }.join(", "), host_ids).map { |row| row.to_a }]
                SELECT id, name FROM hosts
                  WHERE id IN (%s);
              EOS
            end
            result = host_ids.map { |host_id|
              tag_values = Hash[execute(<<-EOS % fields_without_host.map { "?" }.join(", "), [host_id] + fields_without_host).map { |row| row.to_a }]
                SELECT tags.name, GROUP_CONCAT(tags.value, ',') FROM hosts_tags
                  INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE hosts_tags.host_id = ? AND tags.name IN (%s)
                      GROUP BY tags.name;
              EOS
              fields.map { |tag_name|
                if tag_name == "host"
                  host_names.fetch(host_id, "")
                else
                  tag_values.fetch(tag_name, "")
                end
              }
            }
            [result, fields]
          else
            if @options[:listing]
              # TODO: should respect `:primary_tag`?
              fields = execute(<<-EOS % host_ids.map { "?" }.join(", "), host_ids).map { |row| row.first }
                SELECT DISTINCT tags.name FROM hosts_tags
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE hosts_tags.host_id IN (%s);
              EOS
              host_names = Hash[execute(<<-EOS % host_ids.map { "?" }.join(", "), host_ids).map { |row| row.to_a }]
                SELECT id, name FROM hosts
                  WHERE id IN (%s);
              EOS
              result = host_ids.map { |host_id|
                tag_values = Hash[execute(<<-EOS % fields.map { "?" }.join(", "), [host_id] + fields).map { |row| row.to_a }]
                  SELECT tags.name, GROUP_CONCAT(tags.value, ',') FROM hosts_tags
                    INNER JOIN tags ON hosts_tags.tag_id = tags.id
                      WHERE hosts_tags.host_id = ? AND tags.name IN (%s)
                        GROUP BY tags.name;
                EOS
                [host_names.fetch(host_id, "")] + fields.map { |tag_name| tag_values.fetch(tag_name, "") }
              }
              [result, ["host"] + fields]
            else
              if @options[:primary_tag]
                fields = [@options[:primary_tag]]
                result = execute(<<-EOS % host_ids.map { "?" }.join(", "), host_ids + [@options[:primary_tag]]).map { |row| row.to_a }
                  SELECT tags.value FROM hosts_tags
                    INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                    INNER JOIN tags ON hosts_tags.tag_id = tags.id
                      WHERE hosts_tags.host_id IN (%s) AND tags.name = ?;
                EOS
                [result, fields]
              else
                fields = ["host"]
                result = execute(<<-EOS % host_ids.map { "?" }.join(", "), host_ids).map { |row| row.to_a }
                  SELECT name FROM hosts
                    WHERE id IN (%s);
                EOS
                [result, fields]
              end
            end
          end
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
          unless known_tags.empty?
            prepare(memory_db, "INSERT OR IGNORE INTO tags (name, value) VALUES %s" % known_tags.map { "(?, ?)" }.join(", ")).execute(known_tags)
          end

          known_hosts = all_tags.values.reduce(:+).uniq
          unless known_hosts.empty?
            prepare(memory_db, "INSERT OR IGNORE INTO hosts (name) VALUES %s" % known_hosts.map { "(?)" }.join(", ")).execute(known_hosts)
          end

          all_tags.each do |tag, hosts|
            q = []
            q << "INSERT OR REPLACE INTO hosts_tags (host_id, tag_id)"
            q <<   "SELECT host.id, tag.id FROM"
            q <<     "( SELECT id FROM hosts WHERE name IN (%s) ) AS host,"
            q <<     "( SELECT id FROM tags WHERE name = ? AND value = ? LIMIT 1 ) AS tag;"
            unless hosts.empty?
              prepare(memory_db, q.join(" ") % hosts.map { "?" }.join(", ")).execute(hosts + split_tag(tag))
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
          prepare(dst, "INSERT INTO hosts (id, name) VALUES %s" % hosts.map { "(?, ?)" }.join(", ")).execute(hosts) unless hosts.empty?

          tags = prepare(src, "SELECT id, name, value FROM tags").execute().to_a
          prepare(dst, "INSERT INTO tags (id, name, value) VALUES %s" % tags.map { "(?, ?, ?)" }.join(", ")).execute(tags) unless tags.empty?

          hosts_tags = prepare(src, "SELECT host_id, tag_id FROM hosts_tags").to_a
          prepare(dst, "INSERT INTO hosts_tags (host_id, tag_id) VALUES %s" % hosts_tags.map { "(?, ?)" }.join(", ")).execute(hosts_tags) unless hosts_tags.empty?

          create_index_hosts(dst)
          create_index_tags(dst)
          create_index_hosts_tags(dst)
        end
      end

      def create_table_hosts(db)
        logger.debug("create_table_hosts()")
        q = []
        q << "CREATE TABLE IF NOT EXISTS hosts ("
        q <<   "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        q <<   "name VARCHAR(255) NOT NULL COLLATE NOCASE"
        q << ");"
        db.execute(q.join(" "))
      end

      def create_index_hosts(db)
        logger.debug("create_index_hosts()")
        db.execute("CREATE UNIQUE INDEX IF NOT EXISTS hosts_name ON hosts ( name )")
      end

      def create_table_tags(db)
        logger.debug("create_table_tags()")
        q = []
        q << "CREATE TABLE IF NOT EXISTS tags ("
        q <<   "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        q <<   "name VARCHAR(200) NOT NULL COLLATE NOCASE,"
        q <<   "value VARCHAR(200) NOT NULL COLLATE NOCASE"
        q << ");"
        db.execute(q.join(" "))
      end

      def create_index_tags(db)
        logger.debug("create_index_tags()")
        db.execute("CREATE UNIQUE INDEX IF NOT EXISTS tags_name_value ON tags ( name, value )")
      end

      def create_table_hosts_tags(db)
        logger.debug("create_table_hosts_tags()")
        q = []
        q << "CREATE TABLE IF NOT EXISTS hosts_tags ("
        q <<   "host_id INTEGER NOT NULL,"
        q <<   "tag_id INTEGER NOT NULL"
        q << ");"
        db.execute(q.join(" "))
      end

      def create_index_hosts_tags(db)
        logger.debug("create_index_hosts_tags()")
        db.execute("CREATE UNIQUE INDEX IF NOT EXISTS hosts_tags_host_id_tag_id ON hosts_tags ( host_id, tag_id )")
      end
    end
  end
end

# vim:set ft=ruby :
