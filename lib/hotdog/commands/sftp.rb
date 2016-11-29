#!/usr/bin/env ruby

require "json"
require "shellwords"
require "hotdog/commands/ssh"

module Hotdog
  module Commands
    class Sftp < SingularSshAlike
      private
      def build_command_string(host, command=nil, options={})
        cmdline = ["sftp"] + build_command_options(options) + [host]
        if command
          logger.warn("ignore remote command: #{command}")
        end
        Shellwords.join(cmdline)
      end

      def build_command_options(options={})
        cmdline = []
        if options[:forward_agent]
          cmdline << "-o" << "ForwardAgent=yes"
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
