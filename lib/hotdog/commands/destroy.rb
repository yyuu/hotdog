#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Destroy < BaseCommand
      def run(args=[])
        execute(<<-EOS)
          DROP TABLE IF EXISTS hosts;
        EOS
        execute(<<-EOS)
          DROP TABLE IF EXISTS tags;
        EOS
        execute(<<-EOS)
          DROP TABLE IF EXISTS hosts_tags;
        EOS
      end
    end
  end
end

# vim:set ft=ruby :
