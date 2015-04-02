#!/usr/bin/env ruby

require "json"
require "parslet"
require "hotdog/commands/search"
require "shellwords"

module Hotdog
  module Commands
    class Ssh < Search
      def run(args=[])
        ssh_option = {
          index: nil,
          options: [],
          user: nil,
          identity_file: nil,
        }

        optparse.on("-n", "--index INDEX", "Use this index of host if multiple servers are found", Integer) do |index|
          ssh_option[:index] = index
        end
        optparse.on("-o SSH_OPTION", "Passes this string to ssh command through shell. This option may be given multiple times") do |option|
          ssh_option[:options] += [option]
        end
        optparse.on("-i SSH_IDENTITY_FILE", "SSH identity file path") do |path|
          ssh_option[:identity_file] = path
        end
        optparse.on("-u SSH_USER", "SSH login user name") do |user|
          ssh_option[:user] = user
        end

        args = optparse.parse(args)
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

        result = evaluate(node, self).sort

        if result.length == 1
          host = result[0]
        elsif result.empty?
          STDERR.puts("no match found: #{args.join(" ")}")
          exit(1)
        else
          if ssh_option[:index] && result.length > ssh_option[:index]
            host = result[ssh_option[:index]]
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
        ssh_option[:options].each do |option|
          cmdline << "-o" << option
        end
        if path = ssh_option[:identity_file]
          cmdline << "-i" << Shellwords.escape(path)
        end
        if user = ssh_option[:user]
          cmdline << (Shellwords.escape(user) + "@" + address)
        else
          cmdline << address
        end

        exec cmdline.join(" ")
        exit(127)
      end
    end
  end
end
