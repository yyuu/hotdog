#!/usr/bin/env ruby

require "rbconfig"

module Hotdog
  module Commands
    class Version < BaseCommand
      def run(args=[], options={})
        ruby = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["ruby_install_name"])
        exit(system(ruby, $0, "--version") ? 0 : 1)
      end
    end
  end
end

# vim:set ft=ruby :
