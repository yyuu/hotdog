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

        result = evaluate(node, self)

        if result.length == 1
          host = result[0]
        elsif result.empty?
          STDERR.puts("no match found: #{expression}")
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
        if options[:options]
          base_cmdline += options[:options].flat_map { |option| ["-o", option] }
        end
        if options[:port]
          base_cmdline << "-p" << options[:port].to_s
        end
        if options[:verbose]
          base_cmdline << "-v"
        end
        cmdline = base_cmdline + [address]
        if @remote_command
          cmdline << "--" << @remote_command
        end
        logger.debug("execute: #{Shellwords.join(cmdline)}")
        exec(Shellwords.join(cmdline))
        exit(127)
      end
    end
  end
end
