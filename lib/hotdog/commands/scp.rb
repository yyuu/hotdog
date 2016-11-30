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
    end
  end
end
