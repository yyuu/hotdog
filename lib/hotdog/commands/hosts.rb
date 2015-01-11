#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Hosts < BaseCommand
      def run(args=[])
        update

        if args.empty?
          @select_host_id_from_hosts_tags ||= @db.prepare(<<-EOS)
            SELECT DISTINCT host_id FROM hosts_tags;
          EOS
          logger.debug("select_host_id_from_hosts_tags()")
          result = @select_host_id_from_hosts_tags.execute().to_a.reduce(:+)
        else
          if args.map { |host_name| glob?(host_name) }.all?
            args.each do |host_name|
              @insert_or_ignore_into_hosts ||= @db.prepare("INSERT OR IGNORE INTO hosts (name) VALUES (?);")
              logger.debug("insert_or_ignore_into_hosts(%s)" % [host_name.inspect])
              @insert_or_ignore_into_hosts.execute(host_name)
            end
          end
          result = args.map { |host_name|
            if glob?(host_name)
              @select_host_id_from_hosts_tags_by_host_name_glob ||= @db.prepare(<<-EOS)
                SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                  INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                    WHERE LOWER(hosts.name) GLOB LOWER(?);
              EOS
              logger.debug("select_host_id_from_hosts_tags_by_host_name_glob(%s)" % [host_name.inspect])
              @select_host_id_from_hosts_tags_by_host_name_glob.execute(host_name).map { |row| row.first }
            else
              @select_host_id_from_hosts_tags_by_host_name ||= @db.prepare(<<-EOS)
                SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                  INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                    WHERE LOWER(hosts.name) = LOWER(?);
              EOS
              logger.debug("select_host_id_from_hosts_tags_by_host_name(%s)" % [host_name.inspect])
              @select_host_id_from_hosts_tags_by_host_name.execute(host_name).map { |row| row.first }
            end
          }.reduce(:+)
        end
        if 0 < result.length
          result, fields = get_hosts(result)
          STDOUT.print(format(result, fields: fields))
          logger.info("found %d host(s)." % result.length)
        else
          STDERR.puts("no match found: #{args.join(" ")}")
          exit(1)
        end
      end
    end
  end
end

# vim:set ft=ruby :
