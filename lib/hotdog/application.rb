#!/usr/bin/env ruby

require "erb"
require "logger"
require "optparse"
require "shellwords"
require "yaml"
require "hotdog/commands"
require "hotdog/formatters"
require "hotdog/sources"
require "hotdog/version"

module Hotdog
  SQLITE_LIMIT_COMPOUND_SELECT = 500 # TODO: get actual value from `sqlite3_limit()`?

  # only datadog is supported as of Sep 5, 2017
  SOURCE_DATADOG = 0x01

  # | status   | description   |
  # | -------- | ------------- |
  # | 00000000 | pending       |
  # | 00010000 | running       |
  # | 00100000 | shutting-down |
  # | 00110000 | terminated    |
  # | 01000000 | stopping      |
  # | 01010000 | stopped       |
  STATUS_PENDING       = 0b00000000
  STATUS_RUNNING       = 0b00010000
  STATUS_SHUTTING_DOWN = 0b00100000
  STATUS_TERMINATED    = 0b00110000
  STATUS_STOPPING      = 0b01000000
  STATUS_STOPPED       = 0b01010000

  VERBOSITY_NULL  = 0
  VERBOSITY_INFO  = 1
  VERBOSITY_DEBUG = 2
  VERBOSITY_TRACE = 4

  class Application
    def initialize()
      @logger = Logger.new(STDERR)
      @optparse = OptionParser.new
      @optparse.version = Hotdog::VERSION
      @options = {
        endpoint: nil,
        api_key: nil,
        application_key: nil,
        application: self,
        confdir: find_confdir(File.expand_path(".")),
        debug: false,
        expiry: 3600,
        fixed_string: false,
        force: false,
        format: "text",
        headers: false,
        source: "datadog",
        status: nil,
        listing: false,
        logger: @logger,
        max_time: 5,
        offline: false,
        print0: false,
        print1: true,
        print2: false,
        primary_tag: nil,
        tags: [],
        display_search_tags: false,
        verbose: false,
        verbosity: VERBOSITY_NULL,
      }.reject { |key, val|
        # reject nil values to declare sensible default later in subcommand
        val.nil?
      }
      @source_provider = nil # will be initialized later in `main()`
      define_options
    end
    attr_reader :logger
    attr_reader :options
    attr_reader :optparse
    attr_reader :source_provider

    def main(argv=[])
      config = File.join(options[:confdir], "config.yml")
      if File.file?(config)
        begin
          loaded = YAML.load(ERB.new(File.read(config)).result)
        rescue => error
          STDERR.puts("hotdog: failed to load configuration file at #{config.inspect}: #{error}")
          exit(1)
        end
        if Hash === loaded
          @options = @options.merge(Hash[loaded.map { |key, value| [Symbol === key ? key : key.to_s.to_sym, value] }])
        end
      end
      args = @optparse.order(argv)

      begin
        if Hash === @options[:source_alias]
          source_name = @options[:source_alias].fetch(@options[:source], @options[:source])
        else
          source_name = @options[:source]
        end
        @source_provider = get_source(source_name)
      rescue NameError
        STDERR.puts("hotdog: '#{source_name}' is not a valid hotdog source.")
        exit(1)
      end

      begin
        given_command_name = ( args.shift || "help" )
        if Hash === @options[:command_alias]
          command_alias = @options[:command_alias].fetch(given_command_name, given_command_name)
          if Array === command_alias
            command_name, *command_args = command_alias
          else
            command_name, *command_args = Shellwords.shellsplit(command_alias)
          end
        else
          command_name = given_command_name
          command_args = []
        end
        begin
          command = get_command(command_name)
        rescue NameError
          STDERR.puts("hotdog: '#{command_name}' is not a hotdog command.")
          get_command("help").run(["commands"], options)
          exit(1)
        end

        @optparse.banner = "Usage: hotdog #{command_name} [options]"
        command.define_options(@optparse, @options)

        begin
          args = command.parse_options(@optparse, command_args + args)
        rescue OptionParser::ParseError => error
          STDERR.puts("hotdog: #{error.message}")
          command.parse_options(@optparse, ["--help"])
          exit(1)
        end

        if options[:format] == "ltsv"
          options[:headers] = true
        end

        if Hash === @options[:format_alias]
          format_name = @options[:format_alias].fetch(@options[:format], @options[:format])
        else
          format_name = @options[:format]
        end
        options[:formatter] = get_formatter(format_name)

        if ( options[:debug] or options[:verbose] ) and ( options[:verbosity] < VERBOSITY_DEBUG )
          options[:verbosity] = VERBOSITY_DEBUG
        end

        if VERBOSITY_DEBUG <= options[:verbosity]
          options[:logger].level = Logger::DEBUG
        else
          if VERBOSITY_INFO <= options[:verbosity]
            options[:logger].level = Logger::INFO
          else
            options[:logger].level = Logger::WARN
          end
        end

        command.run(args, @options)
      rescue Interrupt
        STDERR.puts("Interrupt")
      rescue Errno::EPIPE => error
        STDERR.puts(error)
      rescue => error
        raise # to show error stacktrace
      end
    end

    def status()
      options.fetch(:status, STATUS_RUNNING)
    end

    def status_name(status=self.status)
      {
        STATUS_PENDING       => "pending",
        STATUS_RUNNING       => "running",
        STATUS_SHUTTING_DOWN => "shutting-down",
        STATUS_TERMINATED    => "terminated",
        STATUS_STOPPING      => "stopping",
        STATUS_STOPPED       => "stopped",
      }.fetch(status, "unknown")
    end

    private
    def define_options
      @optparse.on("--endpoint ENDPOINT", "Datadog API endpoint") do |endpoint|
        options[:endpoint] = endpoint
      end
      @optparse.on("--api-key API_KEY", "Datadog API key") do |api_key|
        options[:api_key] = api_key
      end
      @optparse.on("--application-key APP_KEY", "Datadog application key") do |app_key|
        options[:application_key] = app_key
      end
      @optparse.on("-0", "--null", "Use null character as separator") do |v|
        options[:print0] = v
        options[:print1] = !v
        options[:print2] = !v
      end
      @optparse.on("-1", "Use newline as separator") do |v|
        options[:print0] = !v
        options[:print1] = v
        options[:print2] = !v
      end
      @optparse.on("-2", "Use space as separator") do |v|
        options[:print0] = !v
        options[:print1] = !v
        options[:print2] = v
      end
      @optparse.on("-d", "--[no-]debug", "Enable debug mode") do |v|
        options[:debug] = v
      end
      @optparse.on("--fixed-string", "Interpret pattern as fixed string") do |v|
        options[:fixed_string] = v
      end
      @optparse.on("-f", "--[no-]force", "Enable force mode") do |v|
        options[:force] = v
      end
      @optparse.on("-F FORMAT", "--format FORMAT", "Specify output format") do |format|
        options[:format] = format
      end
      @optparse.on("-h", "--[no-]headers", "Display headeres for each columns") do |v|
        options[:headers] = v
      end
      @optparse.on("--source=SOURCE", "Specify custom host source") do |v|
        @options[:source] = v
      end
      @optparse.on("--status=STATUS", "Specify custom host status") do |v|
        case v
        when /\A\d\z/i
          options[:status] = v.to_i
        when /\A(?:all|any)\z/i
          options[:status] = nil
        when /\A(?:pending)\z/i
          options[:status] = STATUS_PENDING
        when /\A(?:running)\z/i
          options[:status] = STATUS_RUNNING
        when /\A(?:shutting-down)\z/i
          options[:status] = STATUS_SHUTTING_DOWN
        when /\A(?:terminated)\z/i
          options[:status] = STATUS_TERMINATED
        when /\A(?:stopping)\z/i
          options[:status] = STATUS_STOPPING
        when /\A(?:stopped)\z/i
          options[:status] = STATUS_STOPPED
        else
          raise(OptionParser::InvalidArgument.new("unknown status: #{v}"))
        end
      end
      @optparse.on("-l", "--[no-]listing", "Use listing format") do |v|
        options[:listing] = v
      end
      @optparse.on("-a TAG", "-t TAG", "--tag TAG", "Use specified tag name/value") do |tag|
        options[:tags] += [tag]
      end
      @optparse.on("--primary-tag TAG", "Use specified tag as the primary tag") do |tag|
        options[:primary_tag] = tag
      end
      @optparse.on("-q", "--[no-]quiet", "Decrease verbosity") do |v|
        options[:verbosity] -= 1
      end
      @optparse.on("-x", "--display-search-tags", "Show tags used in search expression") do |v|
        options[:display_search_tags] = v
      end
      @optparse.on("-V", "-v", "--[no-]verbose", "Increase verbosity") do |v|
        options[:verbosity] += 1
      end
      @optparse.on("--[no-]offline", "Enable offline mode") do |v|
        options[:offline] = v
      end
    end

    def const_name(name)
      name.to_s.split(/[^\w]+/).map { |s| s.capitalize }.join
    end

    def get_formatter(name)
      begin
        klass = Hotdog::Formatters.const_get(const_name(name))
      rescue NameError
        begin
          require "hotdog/formatters/#{name}"
          klass = Hotdog::Formatters.const_get(const_name(name))
        rescue LoadError
          raise(NameError.new("unknown format: #{name}"))
        end
      end
      klass.new
    end

    def get_command(name)
      begin
        klass = Hotdog::Commands.const_get(const_name(name))
      rescue NameError
        begin
          require "hotdog/commands/#{name}"
          klass = Hotdog::Commands.const_get(const_name(name))
        rescue LoadError
          raise(NameError.new("unknown command: #{name}"))
        end
      end
      klass.new(self)
    end

    def get_source(name)
      begin
        klass = Hotdog::Sources.const_get(const_name(name))
      rescue NameError
        begin
          require "hotdog/sources/#{name}"
          klass = Hotdog::Sources.const_get(const_name(name))
        rescue LoadError
          raise(NameError.new("unknown source: #{name}"))
        end
      end
      klass.new(self)
    end

    def find_library(dirname, name)
      load_path = $LOAD_PATH.map { |path| File.join(path, dirname) }.select { |path| File.directory?(path) }
      libraries = load_path.flat_map { |path| Dir.glob(File.join(path, "*.rb")) }.select { |file| File.file?(file) }
      rbname = "#{name}.rb"
      library = libraries.find { |file| File.basename(file) == rbname }
      if library
        library
      else
        candidates = libraries.map { |file| [file, File.basename(file).slice(0, name.length)] }.select { |_file, s| s == name }
        if candidates.length == 1
          candidates.first.first
        else
          nil
        end
      end
    end

    def find_confdir(path)
      if path == "/"
        # default
        if ENV.has_key?("HOTDOG_CONFDIR")
          ENV["HOTDOG_CONFDIR"]
        else
          File.join(ENV["HOME"], ".hotdog")
        end
      else
        confdir = File.join(path, ".hotdog")
        if File.directory?(confdir)
          confdir
        else
          find_confdir(File.dirname(path))
        end
      end
    end
  end
end

# vim:set ft=ruby :
