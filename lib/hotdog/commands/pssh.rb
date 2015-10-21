#!/usr/bin/env ruby

require "json"
require "parslet"
require "hotdog/commands/search"
require "shellwords"
require "parallel"

module Hotdog
  module Commands
    class Pssh < Search
      def define_options(optparse, options={})
        options[:options] = []
        options[:user] = nil
        options[:port] = nil
        options[:identity_file] = nil
        options[:forward_agent] = false
        options[:max_parallelism] = nil
        options[:color] = :auto
        options[:filter_command] = nil

        optparse.on("-o SSH_OPTION", "Passes this string to ssh command through shell. This option may be given multiple times") do |option|
          options[:options] += [option]
        end
        optparse.on("-i SSH_IDENTITY_FILE", "SSH identity file path") do |path|
          options[:identity_file] = path
        end
        optparse.on("-A", "Enable agent forwarding", TrueClass) do |b|
          options[:forward_agent] = b
        end
        optparse.on("-p PORT", "Port of the remote host", Integer) do |port|
          options[:port] = port
        end
        optparse.on("-u SSH_USER", "SSH login user name") do |user|
          options[:user] = user
        end
        optparse.on("-P PARALLELISM", "Max parallelism", Integer) do |n|
          options[:max_parallelism] = n
        end
        optparse.on("-v", "--verbose", "Enable verbose ode") do |v|
          options[:verbose] = v
        end
        optparse.on("--color=WHEN", "--colour=WHEN", "Enable colors") do |color|
          options[:color] = color
        end
        optparse.on("--filter=COMMAND", "Command to filter search result.") do |command|
          options[:filter_command] = command
        end
      end

      def run(args=[], options={})
        expression = args.join(" ").strip
        if expression.empty?
          # return everything if given expression is empty
          expression = "*"
        end

        begin
          node = parse(expression)
        rescue Parslet::ParseFailed => error
          STDERR.puts("syntax error: " + error.cause.ascii_tree)
          exit(1)
        end

        result0 = evaluate(node, self)
        if 0 < result0.length
          exec_command(result0, options)
        else
          STDERR.puts("no match found: #{expression}")
          exit(1)
        end
      end

      private
      def exec_command(result0, options={})
        result, fields = get_hosts(result0)
        hosts = result.flatten
        threads = options[:max_parallelism] || hosts.size
        use_color_p = use_color?

        if options[:filter_command]
          filtered_hosts = Parallel.map(hosts, in_threads: threads) { |host|
            cmdline = build_command_string(host, options)
            cmdline += " -- #{Shellwords.shellescape(options[:filter_command])}"
            [host, exec_command_real(host, cmdline, false, use_color_p)]
          }.select { |host, stat|
            stat
          }.map { |host, stat|
            host
          }
          if hosts != filtered_hosts
            logger.info("filtered host(s): #{(hosts - filtered_hosts).inspect}")
            hosts = filtered_hosts
          end
        end

        stats = Parallel.map(hosts, in_threads: threads) { |host|
          cmdline = build_command_string(host, options)
          if @remote_command
            cmdline += " -- #{Shellwords.shellescape(@remote_command)}"
          end
          exec_command_real(host, cmdline, true, use_color_p)
        }
        unless stats.all?
          exit(1)
        end
      end

      def build_command_string(host, options={})
        # build ssh command
        cmdline = ["ssh"]
        if options[:forward_agent]
          cmdline << "-A"
        end
        if options[:identity_file]
          cmdline << "-i" << options[:identity_file]
        end
        if options[:user]
          cmdline << "-l" << options[:user]
        end
        cmdline << "-o" << "BatchMode=yes"
        if options[:options]
          cmdline += options[:options].flat_map { |option| ["-o", option] }
        end
        if options[:port]
          cmdline << "-p" << options[:port].to_s
        end
        Shellwords.join(cmdline + [host])
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
