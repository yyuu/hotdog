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
      end

      def parse_options(optparse, args=[])
        if args.index("--")
          @remote_command = args.slice(args.index("--") + 1, args.length).join(" ")
          optparse.parse(args.slice(0, args.index("--")))
        else
          @remote_command = nil
          optparse.parse(args)
        end
      end
      attr_reader :remote_command

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

      def exec_command(result0, options={})
        result, fields = get_hosts(result0)
        hosts = result.flatten
        threads = options[:max_parallelism] || hosts.size
        stats = Parallel.map(hosts.zip(hosts), in_threads: threads) { |host, name|
          if use_color?
            header = "\e[0;36m#{name}\e[00m"
          else
            header = name
          end
          cmdline = build_command_string(host, options)
          logger.debug("execute: #{cmdline}")
          IO.popen(cmdline, in: :close, err: [:child, :out]) do |io|
            io.each_line do |line|
              STDOUT.write("#{header}: #{line}")
            end
          end
          $?.success? # $? is thread-local variable
        }
        unless stats.all?
          exit(1)
        end
      end

      def build_command_string(host, options={})
        # build ssh command
        base_cmdline = ["ssh"]
        if options[:forward_agent]
          base_cmdline << "-A"
        end
        if options[:identity_file]
          base_cmdline << "-i" << options[:identity_file]
        end
        if options[:user]
          base_cmdline << "-l" << options[:user]
        end
        base_cmdline << "-o" << "BatchMode=yes"
        if options[:options]
          base_cmdline += options[:options].flat_map { |option| ["-o", option] }
        end
        if options[:port]
          base_cmdline << "-p" << options[:port].to_s
        end
        cmdline = base_cmdline + [host]
        if @remote_command
          cmdline << "--" << @remote_command
        end
        Shellwords.join(cmdline)
      end

      private
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
    end
  end
end
