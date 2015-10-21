#!/usr/bin/env ruby

require "json"
require "parslet"
require "hotdog/commands/ssh"
require "shellwords"
require "parallel"

module Hotdog
  module Commands
    class Pssh < SshAlike
      def define_options(optparse, options={})
        super
        options[:max_parallelism] = nil
        options[:color] = :auto

        optparse.on("-P PARALLELISM", "Max parallelism", Integer) do |n|
          options[:max_parallelism] = n
        end
        optparse.on("--color=WHEN", "--colour=WHEN", "Enable colors") do |color|
          options[:color] = color
        end
      end

      private
      def parallelism(hosts)
        options[:max_parallelism] || hosts.size
      end

      def filter_hosts(hosts)
        if options[:filter_command]
          use_color_p = use_color?
          filtered_hosts = Parallel.map(hosts, in_threads: parallelism(hosts)) { |host|
            cmdline = build_command_string(host, options[:filter_command], options)
            [host, exec_command_real(host, cmdline, false, use_color_p)]
          }.select { |host, stat|
            stat
          }.map { |host, stat|
            host
          }
          if hosts == filtered_hosts
            hosts
          else
            logger.info("filtered host(s): #{(hosts - filtered_hosts).inspect}")
            filtered_hosts
          end
        else
          hosts
        end
      end

      def exec_command(hosts, options={})
        use_color_p = use_color?
        stats = Parallel.map(hosts, in_threads: parallelism(hosts)) { |host|
          cmdline = build_command_string(host, @remote_command, options)
          exec_command_real(host, cmdline, true, use_color_p)
        }
        if stats.all?
          exit(0)
        else
          exit(1)
        end
      end

      def use_color?
        case options[:color]
        when :always
          true
        when :never
          false
        else
          STDOUT.tty?
        end
      end

      def exec_command_real(identifier, cmdline, output=true, colorize=false)
        logger.debug("execute: #{cmdline}")
        IO.popen(cmdline, in: :close, err: [:child, :out]) do |io|
          io.each_with_index do |s, i|
            if output
              STDOUT.write("\e[0;36m") if colorize
              STDOUT.write("#{identifier}:#{i}:")
              STDOUT.write("\e[0m") if colorize
              STDOUT.write(s)
            end
          end
        end
        $?.success? # $? is thread-local variable
      end
    end
  end
end
