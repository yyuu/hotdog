#!/usr/bin/env ruby

require "rbconfig"

module Hotdog
  module Commands
    class Help < BaseCommand
      def run(args=[], options={})
        commands = command_files.map { |file| File.basename(file, ".rb") }.sort.uniq
        if "commands" == args.first
          STDOUT.puts("hotdog commands are:")
          commands.each do |command|
            STDOUT.puts("- #{command}")
          end
        else
          ruby = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["ruby_install_name"])
          if commands.include?(args.first)
            exit(system(ruby, $0, args.first, "--help") ? 0 : 1)
          else
            exit(system(ruby, $0, "--help") ? 0 : 1)
          end
        end
      end

      private
      def load_path()
        $LOAD_PATH.map { |path| File.join(path, "hotdog/commands") }.select { |path| File.directory?(path) }
      end

      def command_files()
        load_path.flat_map { |path| Dir.glob(File.join(path, "*.rb")) }.select { |file| File.file?(file) }
      end
    end
  end
end

# vim:set ft=ruby :
