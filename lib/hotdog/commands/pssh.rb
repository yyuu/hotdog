#!/usr/bin/env ruby

require "json"
require "parslet"
require "hotdog/commands/search"
require "shellwords"
require "parallel"

module Hotdog
  module Commands
    class Pssh < Search
      def run(args=[])
        ssh_option = {
          options: [],
          user: nil,
          port: nil,
          identity_file: nil,
          max_parallelism: nil,
        }

        optparse.on("-o SSH_OPTION", "Passes this string to ssh command through shell. This option may be given multiple times") do |option|
          ssh_option[:options] += [option]
        end
        optparse.on("-i SSH_IDENTITY_FILE", "SSH identity file path") do |path|
          ssh_option[:identity_file] = path
        end
        optparse.on("-p PORT", "Port of the remote host", Integer) do |port|
          ssh_option[:port] = port
        end
        optparse.on("-u SSH_USER", "SSH login user name") do |user|
          ssh_option[:user] = user
        end
        optparse.on("-P PARALLELISM", "Max parallelism", Integer) do |n|
          ssh_option[:max_parallelism] = n
        end

        search_args = []
        optparse.order!(args) {|search_arg| search_args.push(search_arg) }
        expression = search_args.join(" ").strip
        if expression.empty? || args.empty?
          exit(1)
        end

        begin
          node = parse(expression)
        rescue Parslet::ParseFailed => error
          STDERR.puts("syntax error: " + error.cause.ascii_tree)
          exit(1)
        end

        result = evaluate(node, self).sort
        result, fields = get_hosts(result)

        if result.empty?
          STDERR.puts("no match found: #{search_args.join(" ")}")
          exit(1)
        end

        addresses = result.map {|host| [host.first, host.last] }

        # build ssh command
        cmdline = ["ssh"]
        ssh_option[:options].each do |option|
          cmdline << "-o" << option
        end
        if path = ssh_option[:identity_file]
          cmdline << "-i" << Shellwords.escape(path)
        end
        if port = ssh_option[:port]
          cmdline << "-p" << port.to_s
        end
        if ssh_option[:forward_agent]
          cmdline << "-A"
        end

        cmdline << "-o" << "BatchMode=yes"

        user = ssh_option[:user]

        threads = ssh_option[:max_parallelism] || addresses.size
        stats = Parallel.map(addresses, in_threads: threads) do |address,name|
          c = cmdline.dup
          if user
            c << (user + "@" + address)
          else
            c << address
          end

          c.concat(args)

          IO.popen([*c, in: :close, err: [:child, :out]]) do |io|
            io.each_line {|line|
              STDOUT.write "#{name}: #{line}"
            }
          end
          $?.success?  # $? is thread-local variable
        end

        unless stats.all? {|success| success }
          exit(1)
        end
      end
    end
  end
end
