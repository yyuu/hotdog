#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Rm < BaseCommand
      def run(args=[])
        execute(<<-EOS % args.map { "?" }.join(", "), args).map { |row| row.first }
          DELETE FROM hosts_tags
            WHERE host_id IN
              ( SELECT hosts_tags.host_id FROM hosts_tags
                  INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                    WHERE hosts.name NOT IN (%s) );
        EOS
      end
    end
  end
end

# vim:set ft=ruby :
