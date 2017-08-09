#!/usr/bin/env ruby

require "json"
require "shellwords"
require "hotdog/commands/ssh"

module Hotdog
  module Commands
    class Scp < SingularSshAlike
      def define_options(optparse, options={})
        program_name = File.basename($0, '.*')
        optparse.banner = "Usage: #{program_name} scp [options] pattern -- src @:dst"
        super
      end

      private
      def build_command_string(host, command=nil, options={})
        # replace "@:" by actual hostname
        cmdline = Shellwords.shellsplit(options.fetch(:scp_command, "scp")) + build_command_options(options) + Shellwords.split(command).map { |token| token.gsub(/@(?=:)/, host) }
        Shellwords.join(cmdline)
      end
    end
  end
end
