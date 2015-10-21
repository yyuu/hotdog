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

        optparse.on("-D BIND_ADDRESS", "Specifies a local \"dynamic\" application-level port forwarding") do |bind_address|
          options[:dynamic_port_forward] = bind_address
        end
        optparse.on("-L BIND_ADDRESS", "Specifies that the given port on the local (client) host is to be forwarded to the given host and port on the remote side") do |bind_address|
          options[:port_forward] = bind_address
        end
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
          if result0.length == 1
            exec_command([result0.first], options)
          else
            if options[:index] and options[:index] < result0.length
              exec_command([result0[options[:index]]], options)
            else
              result, fields = get_hosts_with_search_tags(result0, node)

              # add "index" field
              result = result.each_with_index.map { |host, i| [i] + host }
              fields = ["index"] + fields

              STDERR.print(format(result, fields: fields))
              logger.info("found %d host(s)." % result.length)
              exit(1)
            end
          end
        else
          STDERR.puts("no match found: #{expression}")
          exit(1)
        end
        exit(127)
      end

      private
      def exec_command(result0, options={})
        result, fields = get_hosts(result0)
        hosts = result.flatten
        cmdline = build_command_string(hosts.first, options)
        if @remote_command
          cmdline += " -- #{Shellwords.shellescape(@remote_command)}"
        end
        logger.debug("execute: #{cmdline}")
        exec(cmdline)
      end

      def build_command_string(host, options={})
        # build ssh command
        cmdline = ["ssh"]
        if options[:forward_agent]
          cmdline << "-A"
        end
        if options[:dynamic_port_forward]
          cmdline << "-D" << options[:dynamic_port_forward]
        end
        if options[:port_forward]
          cmdline << "-L" << options[:port_forward]
        end
        if options[:identity_file]
          cmdline << "-i" << options[:identity_file]
        end
        if options[:user]
          cmdline << "-l" << options[:user]
        end
        if options[:options]
          cmdline += options[:options].flat_map { |option| ["-o", option] }
        end
        if options[:port]
          cmdline << "-p" << options[:port].to_s
        end
        if options[:verbose]
          cmdline << "-v"
        end
        Shellwords.join(cmdline + [host])
      end
    end
  end
end
