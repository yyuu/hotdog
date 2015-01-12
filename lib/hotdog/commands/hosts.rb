#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Hosts < BaseCommand
      def run(args=[])
        if args.empty?
          result = execute("SELECT DISTINCT host_id FROM hosts_tags").to_a.reduce(:+)
        else
          if args.map { |host_name| glob?(host_name) }.all?
            args.each do |host_name|
              execute("INSERT OR IGNORE INTO hosts (name) VALUES (?)", host_name)
            end
          end
          result = args.map { |host_name|
            if glob?(host_name)
              execute(<<-EOS, host_name).map { |row| row.first }
                SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                  INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                    WHERE LOWER(hosts.name) GLOB LOWER(?);
              EOS
            else
              execute(<<-EOS, host_name).map { |row| row.first }
                SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                  INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                    WHERE LOWER(hosts.name) = LOWER(?);
              EOS
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
