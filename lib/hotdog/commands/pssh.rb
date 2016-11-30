#!/usr/bin/env ruby

require "json"
require "parallel"
require "parslet"
require "shellwords"
require "tempfile"
require "hotdog/commands/ssh"

module Hotdog
  module Commands
    class Pssh < SshAlike
      def define_options(optparse, options={})
        super
        default_option(options, :show_identifier, true)
        optparse.on("--[no-]identifier", "Each output line will be prepended with identifier.") do |identifier|
          options[:show_identifier] = identifier
        end
        optparse.on("--stop-on-error", "Stop execution when a remote command fails (valid only if -P is set)") do |v|
          options[:stop_on_error] = v
        end
      end

      private
      def run_main(hosts, options={})
        if STDIN.tty?
          infile = nil
        else
          infile = Tempfile.new()
          while cs = STDIN.read(4096)
            infile.write(cs)
          end
          infile.flush
          infile.seek(0)
        end
        begin
          hosts_cmdlines = hosts.map { |host|
            [host, build_command_string(host, @remote_command, options)]
          }
          if options[:dry_run]
            stats = hosts_cmdlines.map { |host, cmdline|
              STDOUT.puts(cmdline)
              true
            }
          else
            stats = Parallel.map(hosts_cmdlines.each_with_index.to_a, in_threads: parallelism(hosts)) { |(host, cmdline), i|
              identifier = options[:show_identifier] ? host : nil
              success = exec_command(identifier, cmdline, index: i, output: true, infile: (infile ? infile.path : nil))
              if !success && options[:stop_on_error]
                raise StopException.new
              end
              success
            }
          end
          if stats.all?
            exit(0)
          else
            exit(1)
          end
        rescue StopException
          logger.info("stopped.")
          exit(1)
        end
      end

      class StopException < StandardError
      end
    end
  end
end
