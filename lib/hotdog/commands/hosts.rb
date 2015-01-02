#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Hosts < BaseCommand
      def run(args=[])
        application.run_command("init")
        update_hosts(@options.dup)

        if args.empty?
          @hosts_q1 ||= @db.prepare(<<-EOS)
            SELECT DISTINCT host_id FROM hosts_tags;
          EOS
          logger.debug("hosts_q1()")
          result = @hosts_q1.execute().to_a.reduce(:+)
        else
          result = args.map { |host_name|
            if host_name.index("*")
              @hosts_q2 ||= @db.prepare(<<-EOS)
                SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                  INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                    WHERE LOWER(hosts.name) GLOB LOWER(?);
              EOS
              logger.debug("hosts_q2(%s)" % [host_name.inspect])
              @hosts_q2.execute(host_name).map { |row| row.first }
            else
              @hosts_q3 ||= @db.prepare(<<-EOS)
                SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                  INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                    WHERE LOWER(hosts.name) = LOWER(?);
              EOS
              logger.debug("hosts_q3(%s)" % [host_name.inspect])
              @hosts_q3.execute(host_name).map { |row| row.first }
            end
          }.reduce(:+)
        end
        if 0 < result.length
          result, fields = get_hosts(result)
          STDOUT.print(format(result, fields: fields))
        else
          STDERR.puts("no match found: #{args.join(" ")}")
          exit(1)
        end
      end
    end
  end
end

# vim:set ft=ruby :
