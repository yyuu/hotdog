#!/usr/bin/env ruby

require "json"
require "parallel"
require "parslet"
require "shellwords"
require "hotdog/commands/ssh"

module Hotdog
  module Commands
    class Pssh < SshAlike
      private
      def run_main(hosts, options={})
        use_color_p = use_color?
        stats = Parallel.map(hosts, in_threads: parallelism(hosts)) { |host|
          cmdline = build_command_string(host, @remote_command, options)
          exec_command(host, cmdline, true, use_color_p)
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
