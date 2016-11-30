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
    end
  end
end
