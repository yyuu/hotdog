#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Hosts < BaseCommand
      def run(args=[])
        args = optparse.parse(args)
        if args.empty?
          result = execute("SELECT DISTINCT host_id FROM hosts_tags").to_a.reduce(:+)
        else
          result = args.map { |host_name|
            q = []
            if glob?(host_name)
              q << "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags"
              q <<   "INNER JOIN hosts ON hosts_tags.host_id = hosts.id"
              q <<     "WHERE hosts.name GLOB ?;"
            else
              q << "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags"
              q <<   "INNER JOIN hosts ON hosts_tags.host_id = hosts.id"
              q <<     "WHERE hosts.name = ?;"
            end
            execute(q.join(" "), [host_name]).map { |row| row.first }
          }.reduce(:+)
        end
        if result && (0 < result.length)
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
