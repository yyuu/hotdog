#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Gc < BaseCommand
      def run(args=[])
        application.run_command("init")
        execute(<<-EOS)
          DELETE FROM hosts WHERE id NOT IN ( SELECT DISTINCT host_id FROM hosts_tags );
        EOS
        execute(<<-EOS)
          DELETE FROM tags WHERE id NOT IN ( SELECT DISTINCT tag_id FROM hosts_tags );
        EOS
      end
    end
  end
end

# vim:set ft=ruby :
