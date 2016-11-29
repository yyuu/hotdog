#!/usr/bin/env ruby

require "json"
require "shellwords"
require "hotdog/commands/ssh"

module Hotdog
  module Commands
    class Scp < SingularSshAlike
      private
      def build_command_string(host, command=nil, options={})
        # replace "@:" by actual hostname
        cmdline = ["scp"] + build_command_options(options) + Shellwords.split(command).map { |token| token.gsub(/@(?=:)/, host) }
        Shellwords.join(cmdline)
      end

      def build_command_options(options={})
        cmdline = []
        if options[:forward_agent]
          # nop
        end
        if options[:ssh_config]
          cmdline << "-F" << File.expand_path(options[:ssh_config])
        end
        if options[:identity_file]
          cmdline << "-i" << options[:identity_file]
        end
        if options[:user]
          cmdline << "-o" << "User=#{options[:user]}"
        end
        if options[:options]
          cmdline += options[:options].flat_map { |option| ["-o", option] }
        end
        if options[:port]
          cmdline << "-P" << options[:port]
        end
        if options[:verbose]
          cmdline << "-v"
        end
        cmdline
      end
    end
  end
end
