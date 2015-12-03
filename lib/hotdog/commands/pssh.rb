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
        options[:show_tag] = true

        optparse.on("--[no-]tag", "Each output line will be prepended with identifier.") do |tag|
          options[:show_tag] = tag
        end
      end

      private
      def run_main(hosts, options={})
        stats = Parallel.map(hosts.each_with_index.to_a, in_threads: parallelism(hosts)) { |host, i|
          cmdline = build_command_string(host, @remote_command, options)
          identifier = options[:show_tag] ? host : nil
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
