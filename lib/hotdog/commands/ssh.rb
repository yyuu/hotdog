#!/usr/bin/env ruby

require "json"
require "parslet"
require "shellwords"
require "thread"
require "hotdog/commands/search"

module Hotdog
  module Commands
    class SshAlike < Search
      def define_options(optparse, options={})
        default_option(options, :ssh_options, {})
        default_option(options, :color, :auto)
        default_option(options, :max_parallelism, Parallel.processor_count * 2)
        default_option(options, :shuffle, false)
        default_option(options, :ssh_config, nil)
        optparse.on("-C", "Enable compression.") do |v|
          options[:ssh_options]["Compression"] = "yes"
        end
        optparse.on("-F SSH_CONFIG", "Specifies an alternative per-user SSH configuration file.") do |configfile|
          options[:ssh_config] = configfile
        end
        optparse.on("--dry-run", "Dry run.") do |v|
          options[:dry_run] = v
        end
        optparse.on("-o SSH_OPTION", "Passes this string to ssh command through shell. This option may be given multiple times") do |ssh_option|
          ssh_option_key, ssh_option_value = ssh_option.split("=", 2)
          options[:ssh_options][ssh_option_key] = ssh_option_value
        end
        optparse.on("-i SSH_IDENTITY_FILE", "SSH identity file path") do |path|
          options[:ssh_options]["IdentityFile"] = path
        end
        optparse.on("-A", "Enable agent forwarding", TrueClass) do |b|
          options[:ssh_options]["ForwardAgent"] = "yes"
        end
        optparse.on("-p PORT", "Port of the remote host", Integer) do |port|
          options[:ssh_options]["Port"] = port
        end
        optparse.on("-u SSH_USER", "SSH login user name") do |user|
          options[:ssh_options]["User"] = user
        end
        optparse.on("--filter=COMMAND", "Command to filter search result.") do |command|
          options[:filter_command] = command
        end
        optparse.on("-P PARALLELISM", "Max parallelism", Integer) do |n|
          options[:max_parallelism] = n
        end
        optparse.on("--color=WHEN", "--colour=WHEN", "Enable colors") do |color|
          options[:color] = color
        end
        optparse.on("--shuffle", "Shuffle result") do |v|
          options[:shuffle] = v
        end
      end

      def run(args=[], options={})
        expression = rewrite_expression(args.join(" ").strip)

        begin
          node = parse(expression)
        rescue Parslet::ParseFailed => error
          STDERR.puts("syntax error: " + error.cause.ascii_tree)
          exit(1)
        end

        result0 = evaluate(node, self)
        tuples, fields = get_hosts_with_search_tags(result0, node)
        tuples = filter_hosts(tuples)
        validate_hosts!(tuples, fields)
        logger.info("target host(s): #{tuples.map {|tuple| tuple.first }.inspect}")
        run_main(tuples.map {|tuple| tuple.first }, options)
      end

      private
      def rewrite_expression(expression)
        expression = super(expression)
        if options[:shuffle]
          expression = "SHUFFLE((#{expression}))"
        end
        expression
      end

      def parallelism(hosts)
        [options[:max_parallelism], hosts.size].compact.min
      end

      def filter_hosts(tuples)
        if options[:filter_command]
          filtered_tuples = Parallel.map(tuples, in_threads: parallelism(tuples)) { |tuple|
            cmdline = build_command_string(tuple.first, options[:filter_command], options)
            [tuple, exec_command(tuple.first, cmdline, output: false)]
          }.select { |_host, stat|
            stat
          }.map { |tuple, _stat|
            tuple
          }
          if tuples == filtered_tuples
            tuples
          else
            logger.info("filtered host(s): #{(tuples - filtered_tuples).map {|tuple| tuple.first }.inspect}")
            filtered_tuples
          end
        else
          tuples
        end
      end

      def validate_hosts!(tuples, fields)
        if tuples.length < 1
          logger.error("no match found")
          exit(1)
        end
      end

      def run_main(hosts, options={})
        raise(NotImplementedError)
      end

      def build_command_options(options={})
        cmdline = []
        if options[:ssh_config]
          cmdline << "-F" << File.expand_path(options[:ssh_config])
        end
        cmdline += options[:ssh_options].flat_map { |k, v| ["-o", "#{k}=#{v}"] }
        if VERBOSITY_TRACE <= options[:verbosity]
          cmdline << "-v"
        end
        cmdline
      end

      def build_command_string(host, command=nil, options={})
        # build ssh command
        cmdline = Shellwords.shellsplit(options.fetch(:ssh_command, "ssh")) + build_command_options(options) + [host]
        if command
          cmdline << "--" << command
        end
        Shellwords.join(cmdline)
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

      def exec_command(identifier, cmdline, options={})
        output = options.fetch(:output, true)
        output_lock = options[:output_lock] || Mutex.new
        logger.debug("execute: #{cmdline}")
        if use_color?
          color = color_code(options[:index])
        else
          color = nil
        end
        if options[:infile]
          cmdline = "cat #{Shellwords.shellescape(options[:infile])} | #{cmdline}"
        end
        cmderr, child_cmderr = IO.pipe
        IO.popen(cmdline, in: :close, err: child_cmderr) do |cmdout|
          i = 0
          each_readable([cmderr, cmdout]) do |readable|
            raw = readable.readline
            if output
              output_lock.synchronize do
                if readable == cmdout
                  STDOUT.puts(prettify_output(raw, i, color, identifier))
                  i += 1
                else
                  STDERR.puts(prettify_output(raw, nil, nil, identifier))
                end
              end
            end
          end
        end
        $?.success? # $? is thread-local variable
      end

      private
      def each_readable(read_list, timeout=1)
        loop do
          # we cannot look until IO#eof? since it will block for pipes
          # http://ruby-doc.org/core-2.4.0/IO.html#method-i-eof-3F
          rs = Array(IO.select(read_list, [], [], timeout)).first
          if r = Array(rs).first
            begin
              yield r
            rescue EOFError => error
              break
            end
          end
        end
      end

      def color_code(index)
        if index
          color = 31 + (index % 6)
        else
          color = 36
        end
      end

      def prettify_output(raw, i, color, identifier)
        buf = []
        if identifier
          if color
            buf << ("\e[0;#{color}m")
          end
          buf << identifier
          buf << ":"
          if i
            buf << i.to_s
            buf << ":"
          end
          if color
            buf << "\e[0m"
          end
        end
        buf << raw
        buf.join
      end
    end

    class SingularSshAlike < SshAlike
      def define_options(optparse, options={})
        super
        options[:index] = nil
        optparse.on("-n", "--index INDEX", "Use this index of host if multiple servers are found", Integer) do |index|
          options[:index] = index
        end
      end

      private
      # rewriting `options[:index]` as SLICE expression won't work as expected with hosts' status
      # since the result may be filtered again with using the status,
      # the filtering needs to be done after the `evaluate()`.
      #
      # for now we need to keep using `filter_hosts()` in favor of `rewrite_expression() to do
      # the filtering based on status filtering.
      def filter_hosts(tuples)
        tuples = super
        if options[:index] and options[:index] < tuples.length
          filtered_tuples = tuples.reject.with_index { |tuple, i| i == options[:index] }
          logger.warn("filtered host(s): #{filtered_tuples.map { |tuple| tuple.first }.inspect}")
          [tuples[options[:index]]]
        else
          tuples
        end
      end

      def validate_hosts!(tuples, fields)
        super
        if tuples.length != 1
          result = tuples.each_with_index.map { |tuple, i| [i] + tuple }
          STDERR.print(format(result, fields: ["index"] + fields))
          logger.error("found %d candidates. use '-n INDEX' option to select one." % result.length)
          exit(1)
        end
      end

      def run_main(hosts, options={})
        cmdline = build_command_string(hosts.first, @remote_command, options)
        logger.debug("execute: #{cmdline}")
        if options[:dry_run]
          STDOUT.puts(cmdline)
          exit(0)
        else
          exec(cmdline)
        end
        exit(127)
      end
    end

    class Ssh < SingularSshAlike
      def define_options(optparse, options={})
        super
        optparse.on("-D BIND_ADDRESS", "Specifies a local \"dynamic\" application-level port forwarding") do |bind_address|
          options[:dynamic_port_forward] = bind_address
        end
        optparse.on("-L BIND_ADDRESS", "Specifies that the given port on the local (client) host is to be forwarded to the given host and port on the remote side") do |bind_address|
          options[:port_forward] = bind_address
        end
      end

      private
      def build_command_options(options={})
        arguments = super
        if options[:dynamic_port_forward]
          arguments << "-D" << options[:dynamic_port_forward]
        end
        if options[:port_forward]
          arguments << "-L" << options[:port_forward]
        end
        arguments
      end
    end
  end
end
