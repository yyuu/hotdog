#!/usr/bin/env ruby

require "fileutils"
require "dogapi"
require "json"
require "sqlite3"

module Hotdog
  module Commands
    class BaseCommand
      def initialize(options={})
        @fixed_string = options[:fixed_string]
        @force = options[:force]
        @formatter = options[:formatter]
        @logger = options[:logger]
        @tags = options[:tags]
        @application = options[:application]
        @options = options
        @dog = Dogapi::Client.new(options[:api_key], options[:application_key])
        @expiry = options[:expiry]
      end
      attr_reader :application
      attr_reader :expiry
      attr_reader :force
      attr_reader :formatter
      attr_reader :logger
      attr_reader :tags
      attr_reader :options

      def run(args=[])
        raise(NotImplementedError)
      end

      def execute(query, *args)
        update_db
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

      private
      def format(result, options={})
        @formatter.format(result, @options.merge(options))
      end

      def glob?(s)
        s.index('*') or s.index('?') or s.index('[') or s.index(']')
      end

      def get_hosts(hosts=[])
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
          if options[:listing]

            fields = []
            hosts = execute(<<-EOS % hosts.map { "?" }.join(", "), hosts)
              SELECT id, name FROM hosts WHERE id IN (%s) ORDER BY name;
            EOS
            result = hosts.map { |host_id, host_name|
              tag_names = select_tag_names_from_hosts_tags_by_host_id(@db, host_id)
              tag_names.each do |tag_name|
                fields << tag_name unless fields.index(tag_name)
              end
              [host_name] + fields.map { |tag_name|
                select_tag_values_from_hosts_tags_by_host_id_and_tag_name(@db, host_id, tag_name)
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

      def update_db(options={})
        if @db.nil?
          FileUtils.mkdir_p(@options[:confdir])
          persistent = File.join(@options[:confdir], "persistent.db")

          if not @force and File.exist?(persistent) and Time.new < File.mtime(persistent) + expiry
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

          code, result = @dog.all_tags()
          logger.debug("dog.all_tags() #==> [%s, ...]" % [code.inspect])
          if code.to_i / 100 != 2
            raise("dog.all_tags() returns (%s: ...)" % [code.inspect])
          end

          result["tags"].each do |tag, hosts|
            tag_name, tag_value = tag.split(":", 2)
            tag_value ||= ""
            insert_or_ignore_into_tags(memory_db, tag_name, tag_value)
            hosts.each do |host_name|
              insert_or_ignore_into_hosts(memory_db, host_name)
              insert_or_replace_into_hosts_tags(memory_db, host_name, tag_name, tag_value)
            end
          end

          # backup in-memory db to file
          FileUtils.rm_f(persistent)
          persistent_db = SQLite3::Database.new(persistent)
          copy_db(memory_db, persistent_db)
          persistent_db.close
          @db = memory_db
        else
          @db
        end
      end

      def copy_db(src, dst)
        # create index later for better insert performance
        dst.transaction do
          create_table_hosts(dst)
          create_table_tags(dst)
          create_table_hosts_tags(dst)

          select_from_hosts(src).each do |host_id, host_name|
            insert_into_hosts(dst, host_id, host_name)
          end
          select_from_tags(src).each do |tag_id, tag_name, tag_value|
            insert_into_tags(dst, tag_id, tag_name, tag_value)
          end
          select_from_hosts_tags(src).each do |host_id, tag_id|
            insert_into_hosts_tags(dst, host_id, tag_id)
          end

          create_index_hosts(dst)
          create_index_tags(dst)
          create_index_hosts_tags(dst)
        end
      end

      def select_from_hosts(db)
        logger.debug("select_from_hosts()")
        db.execute("SELECT id, name FROM hosts")
      end

      def select_from_tags(db)
        logger.debug("select_from_tags()")
        db.execute("SELECT id, name, value FROM tags")
      end

      def select_from_hosts_tags(db)
        logger.debug("from_hosts_tags()")
        db.execute("SELECT host_id, tag_id FROM hosts_tags")
      end

      def create_table_hosts(db)
        logger.debug("create_table_hosts()")
        db.execute(<<-EOS)
          CREATE TABLE IF NOT EXISTS hosts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(255) NOT NULL
          );
        EOS
      end

      def drop_table_hosts(db)
        logger.debug("drop_table_hosts()")
        db.execute("DROP TABLE IF EXISTS hosts")
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
            name VARCHAR(200) NOT NULL,
            value VARCHAR(200) NOT NULL DEFAULT ""
          );
        EOS
      end

      def drop_table_tags(db)
        logger.debug("drop_table_tags()")
        db.execute("DROP TABLE IF EXISTS tags")
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

      def drop_table_hosts_tags(db)
        logger.debug("drop_table_hosts_tags()")
        db.execute("DROP TABLE IF EXISTS hosts_tags")
      end

      def create_index_hosts_tags(db)
        logger.debug("create_index_hosts_tags()")
        db.execute("CREATE UNIQUE INDEX IF NOT EXISTS hosts_tags_host_id_tag_id ON hosts_tags ( host_id, tag_id )")
      end

      def insert_into_tags(db, tag_id, tag_name, tag_value)
        logger.debug("insert_into_tags(%s, %s, %s)" % [tag_id.inspect, tag_name.inspect, tag_value.inspect])
        db.execute("INSERT INTO tags (id, name, value) VALUES (?, ?, ?)", tag_id, tag_name, tag_value)
      end

      def insert_or_ignore_into_tags(db, tag_name, tag_value)
        logger.debug("insert_or_ignore_into_tags(%s, %s)" % [tag_name.inspect, tag_value.inspect])
        db.execute("INSERT OR IGNORE INTO tags (name, value) VALUES (?, ?)", tag_name, tag_value)
      end

      def insert_into_hosts(db, host_id, host_name)
        logger.debug("insert_into_hosts(%s, %s)" % [host_id.inspect, host_name.inspect])
        db.execute("INSERT INTO hosts (id, name) VALUES (?, ?)", host_id, host_name)
      end

      def insert_or_ignore_into_hosts(db, host_name)
        logger.debug("insert_or_ignore_into_hosts(%s)" % [host_name.inspect])
        db.execute("INSERT OR IGNORE INTO hosts (name) VALUES (?)", host_name)
      end

      def insert_into_hosts_tags(db, host_id, tag_id)
        logger.debug("insert_into_hosts_tags(%s, %s)" % [host_id.inspect, tag_id.inspect])
        db.execute("INSERT INTO hosts_tags (host_id, tag_id) VALUES (?, ?)", host_id, tag_id)
      end

      def insert_or_replace_into_hosts_tags(db, host_name, tag_name, tag_value)
        logger.debug("insert_or_replace_into_hosts_tags(%s, %s, %s)" % [host_name.inspect, tag_name.inspect, tag_value.inspect])
        db.execute(<<-EOS, host_name, tag_name, tag_value)
          INSERT OR REPLACE INTO hosts_tags (host_id, tag_id)
            SELECT host.id, tag.id FROM
              ( SELECT id FROM hosts WHERE name = ? ) AS host,
              ( SELECT id FROM tags WHERE name = ? AND value = ? ) AS tag;
        EOS
      end

      def select_name_from_hosts_by_id(db, host_id)
        logger.debug("select_name_from_hosts_by_id(%s)" % [host_id.inspect])
        db.execute("SELEC name FROM hosts WHERE id = ? LIMIT 1", host_id).map { |row| row.first }.first
      end

      def select_tag_values_from_hosts_tags_by_host_id_and_tag_name_glob(db, host_id, tag_name)
        logger.debug("select_tag_values_from_hosts_tags_by_host_id_and_tag_name_glob(%s, %s)", host_id.inspect, tag_name.inspect)
        db.execute(<<-EOS, host_id, tag_name).map { |row| row.first }.join(",")
          SELECT tags.value FROM hosts_tags
            INNER JOIN tags ON hosts_tags.tag_id = tags.id
              WHERE hosts_tags.host_id = ? AND tags.name GLOB ?;
        EOS
      end

      def select_tag_values_from_hosts_tags_by_host_id_and_tag_name(db, host_id, tag_name)
        logger.debug("select_tag_values_from_hosts_tags_by_host_id_and_tag_name(%s, %s)" % [host_id.inspect, tag_name.inspect])
        db.execute(<<-EOS, host_id, tag_name).map { |row| row.first }.join(",")
          SELECT tags.value FROM hosts_tags
            INNER JOIN tags ON hosts_tags.tag_id = tags.id
              WHERE hosts_tags.host_id = ? AND tags.name = ?;
        EOS
      end

      def select_tag_names_from_hosts_tags_by_host_id(db, host_id)
        logger.debug("select_tag_names_from_hosts_tags_by_host_id(%s)" % [host_id.inspect])
        db.execute(<<-EOS, host_id).map { |row| row.first }
          SELECT DISTINCT tags.name FROM hosts_tags
            INNER JOIN tags ON hosts_tags.tag_id = tags.id
              WHERE hosts_tags.host_id = ?;
        EOS
      end
    end
  end
end

# vim:set ft=ruby :
