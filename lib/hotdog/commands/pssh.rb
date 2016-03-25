#!/usr/bin/env ruby

require "json"
require "parallel"
require "parslet"
require "shellwords"
require "hotdog/commands/ssh"

module Hotdog
  module Commands
    class Pssh < SshAlike
      def define_options(optparse, options={})
        default_option(options, :show_identifier, true)
        super
        optparse.on("--[no-]identifier", "Each output line will be prepended with identifier.") do |identifier|
          options[:show_identifier] = identifier
        end
      end

      private
      def run_main(hosts, options={})
        stats = Parallel.map(hosts.each_with_index.to_a, in_threads: parallelism(hosts)) { |host, i|
          cmdline = build_command_string(host, @remote_command, options)
          identifier = options[:show_identifier] ? host : nil
          exec_command(identifier, cmdline, index: i, output: true)
        }
        if stats.all?
          exit(0)
        else
          exit(1)
        end
      end
    end
  end
end
