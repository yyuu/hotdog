#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Hosts < BaseCommand
      def run(args=[])
#       application.run_command("init")

        if args.empty?
#         update_hosts(@options.dup)
          @hosts_q1 ||= @db.prepare(<<-EOS)
            SELECT DISTINCT host_id FROM hosts_tags;
          EOS
          logger.debug("hosts_q1()")
          result = @hosts_q1.execute().to_a.reduce(:+)
        else
          if args.map { |host_name| glob?(host_name) }.any?
#           update_hosts(@options.dup)
          else
            args.each do |host_name|
              @hosts_q4 ||= @db.prepare("INSERT OR IGNORE INTO hosts (name) VALUES (?);")
              logger.debug("hosts_q4(%s)" % [host_name.inspect])
              @hosts_q4.execute(host_name)
#             update_host_tags(host_name, @options.dup)
            end
          end
          result = args.map { |host_name|
            if glob?(host_name)
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
