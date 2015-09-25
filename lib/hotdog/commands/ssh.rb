#!/usr/bin/env ruby

require "json"
require "parslet"
require "hotdog/commands/search"
require "shellwords"

module Hotdog
  module Commands
    class Ssh < Search
      def define_options(optparse)
        @ssh_options = @options.merge({
          index: nil,
          options: [],
          user: nil,
          port: nil,
          identity_file: nil,
          forward_agent: false,
          verbose: false,
        })

        optparse.on("-n", "--index INDEX", "Use this index of host if multiple servers are found", Integer) do |index|
          @ssh_options[:index] = index
        end
        optparse.on("-o SSH_OPTION", "Passes this string to ssh command through shell. This option may be given multiple times") do |option|
          @ssh_options[:options] += [option]
        end
        optparse.on("-i SSH_IDENTITY_FILE", "SSH identity file path") do |path|
          @ssh_options[:identity_file] = path
        end
        optparse.on("-A", "Enable agent forwarding", TrueClass) do |b|
          @ssh_options[:forward_agent] = b
        end
        optparse.on("-p PORT", "Port of the remote host", Integer) do |port|
          @ssh_options[:port] = port
        end
        optparse.on("-u SSH_USER", "SSH login user name") do |user|
          @ssh_options[:user] = user
        end
        optparse.on("-v", "--verbose", "Enable verbose ode") do |v|
          @ssh_options[:verbose] = v
        end
      end

      def parse_options(optparse, args=[])
      end

      def run(args=[])
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
          if @ssh_options[:index] && result.length > @ssh_options[:index]
            host = result[@ssh_options[:index]]
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
        @ssh_options[:options].each do |option|
          cmdline << "-o" << option
        end
        if path = @ssh_options[:identity_file]
          cmdline << "-i" << Shellwords.escape(path)
        end
        if port = @ssh_options[:port]
          cmdline << "-p" << port.to_s
        end
        if @ssh_options[:forward_agent]
          cmdline << "-A"
        end
        if @ssh_options[:verbose]
          cmdline << "-v"
        end
        if user = @ssh_options[:user]
          cmdline << (user + "@" + address)
        else
          cmdline << address
        end
        cmdline.concat(args)

        exec(*cmdline)
        exit(127)
      end
    end
  end
end
