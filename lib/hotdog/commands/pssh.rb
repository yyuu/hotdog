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
        options[:max_parallelism] = nil

        optparse.on("-o SSH_OPTION", "Passes this string to ssh command through shell. This option may be given multiple times") do |option|
          options[:options] += [option]
        end
        optparse.on("-i SSH_IDENTITY_FILE", "SSH identity file path") do |path|
          options[:identity_file] = path
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
      end

      def run(args=[], options={})
        use_color = STDOUT.tty?
        expression = args.join(" ").strip
        if expression.empty? || args.empty?
          exit(1)
        end

        begin
          node = parse(expression)
        rescue Parslet::ParseFailed => error
          STDERR.puts("syntax error: " + error.cause.ascii_tree)
          exit(1)
        end

        result = evaluate(node, self)
        result, fields = get_hosts(result)

        if result.empty?
          STDERR.puts("no match found: #{search_args.join(" ")}")
          exit(1)
        end

        addresses = result.map {|host| [host.first, host.last] }

        # build ssh command
        cmdline = ["ssh"]
        options[:options].each do |option|
          cmdline << "-o" << option
        end
        if path = options[:identity_file]
          cmdline << "-i" << Shellwords.escape(path)
        end
        if port = options[:port]
          cmdline << "-p" << port.to_s
        end
        if options[:forward_agent]
          cmdline << "-A"
        end

        cmdline << "-o" << "BatchMode=yes"

        user = options[:user]

        threads = options[:max_parallelism] || addresses.size
        stats = Parallel.map(addresses, in_threads: threads) { |address,name|
          if use_color
            header = "\e[0;36m#{name}\e[00m"
          else
            header = name
          end
          c = cmdline.dup
          if user
            c << (user + "@" + address)
          else
            c << address
          end
          logger.debug("execute: #{Shellwords.join(c)}")
          IO.popen([*c, in: :close, err: [:child, :out]]) do |io|
            io.each_line do |line|
              STDOUT.write "#{header}: #{line}"
            end
          end
          $?.success? # $? is thread-local variable
        }

        unless stats.all?
          exit(1)
        end
      end
    end
  end
end
