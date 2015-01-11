#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Update < BaseCommand
      def run(args=[])
        update_tags(@options.dup)
      end
    end
  end
end

# vim:set ft=ruby :
