#!/usr/bin/env ruby

require "json"
require "parslet"
require "hotdog/commands/search"
require "shellwords"

module Hotdog
  module Commands
    class Ssh < Search
      def define_options(optparse, options={})
        options[:index] = nil
        options[:options] = []
        options[:user] = nil
        options[:port] = nil
        options[:identity_file] = nil
        options[:forward_agent] = false
        options[:verbose] = false

        optparse.on("-n", "--index INDEX", "Use this index of host if multiple servers are found", Integer) do |index|
          options[:index] = index
        end
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
        optparse.on("-v", "--verbose", "Enable verbose ode") do |v|
          options[:verbose] = v
        end
      end

      def run(args=[], options={})
        expression = args.join(" ").strip
        if expression.empty?
          exit(1)
        end

        begin
          node = parse(expression)
        rescue Parslet::ParseFailed => error
          STDERR.puts("syntax error: " + error.cause.ascii_tree)
          exit(1)
        end

        result = evaluate(node, self)

        if result.length == 1
          host = result[0]
        elsif result.empty?
          STDERR.puts("no match found: #{search_args.join(" ")}")
          exit(1)
        else
          if options[:index] && result.length > options[:index]
            host = result[options[:index]]
          else
            result, fields = get_hosts_with_search_tags(result, node)

            # add "index" field
            result = result.each_with_index.map {|host,i| [i] + host }
            fields = ["index"] + fields

            STDERR.print(format(result, fields: fields))
            logger.info("found %d host(s)." % result.length)
            exit(1)
          end
        end

        result, fields = get_hosts([host])
        address = result.flatten.first

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
        if options[:verbose]
          cmdline << "-v"
        end
        if user = options[:user]
          cmdline << (user + "@" + address)
        else
          cmdline << address
        end
        logger.debug("execute: #{Shellwords.join(cmdline)}")
        exec(*cmdline)
        exit(127)
      end
    end
  end
end
