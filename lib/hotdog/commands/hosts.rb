#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Hosts < BaseCommand
      def run(args=[])
        update_hosts(@options.dup)

        if args.empty?
          result = execute(<<-EOS).map { |row| row.first }
            SELECT DISTINCT host_id FROM hosts_tags;
          EOS
        else
          result = args.map { |host_name|
            if host_name.index("*")
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
          STDOUT.puts(format(result, fields: fields))
        else
          STDERR.puts("no match found: #{args.join(" ")}")
          exit(1)
        end
      end
    end
  end
end

# vim:set ft=ruby :
