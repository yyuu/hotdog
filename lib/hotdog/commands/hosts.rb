#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Hosts < BaseCommand
      def run(args=[])
        args = optparse.parse(args)
        if args.empty?
          result = execute("SELECT id FROM hosts").to_a.reduce(:+)
        else
          result = args.flat_map { |host_name|
            if glob?(host_name)
              execute("SELECT id FROM hosts WHERE name GLOB ?", [host_name]).to_a.reduce(:+)
            else
              execute("SELECT id FROM hosts WHERE name = ?", [host_name]).to_a.reduce(:+)
            end
          }
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
