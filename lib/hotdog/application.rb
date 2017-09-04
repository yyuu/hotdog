#!/usr/bin/env ruby

require "erb"
require "logger"
require "optparse"
require "yaml"
require "hotdog/commands"
require "hotdog/formatters"
require "hotdog/version"

module Hotdog
  SQLITE_LIMIT_COMPOUND_SELECT = 500 # TODO: get actual value from `sqlite3_limit()`?

  HOST_MODE_DEFAULT = 0
  HOST_MODE_MAINTENANCE = 1

  class Application
    def initialize()
      @logger = Logger.new(STDERR).tap { |logger|
        logger.level = Logger::INFO
      }
      @optparse = OptionParser.new
      @optparse.version = Hotdog::VERSION
      @options = {
        endpoint: ENV.fetch("DATADOG_HOST", "https://app.datadoghq.com"),
        api_key: ENV["DATADOG_API_KEY"],
        application_key: ENV["DATADOG_APPLICATION_KEY"],
        application: self,
        confdir: find_confdir(File.expand_path(".")),
        debug: false,
        expiry: 3600,
        fixed_string: false,
        force: false,
        format: "text",
        headers: false,
        host_mode: HOST_MODE_DEFAULT, # FIXME: better naming?
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
      }
      define_options
    end
    attr_reader :logger
    attr_reader :options
    attr_reader :optparse

    def main(argv=[])
      config = File.join(options[:confdir], "config.yml")
      if File.file?(config)
        loaded = YAML.load(ERB.new(File.read(config)).result)
        if Hash === loaded
          @options = @options.merge(Hash[loaded.map { |key, value| [Symbol === key ? key : key.to_s.to_sym, value] }])
        end
      end
      args = @optparse.order(argv)

      begin
        command_name = ( args.shift || "help" )
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
          args = command.parse_options(@optparse, args)
        rescue OptionParser::ParseError => error
          STDERR.puts("hotdog: #{error.message}")
          command.parse_options(@optparse, ["--help"])
          exit(1)
        end

        if options[:format] == "ltsv"
          options[:headers] = true
        end

        options[:formatter] = get_formatter(options[:format])

        if options[:debug] or options[:verbose]
          options[:logger].level = Logger::DEBUG
        else
          options[:logger].level = Logger::INFO
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

    def api_key()
      if options[:api_key]
        options[:api_key]
      else
        update_api_key!
        if options[:api_key]
          options[:api_key]
        else
          raise("DATADOG_API_KEY is not set")
        end
      end
    end

    def application_key()
      if options[:application_key]
        options[:application_key]
      else
        update_application_key!
        if options[:application_key]
          options[:application_key]
        else
          raise("DATADOG_APPLICATION_KEY is not set")
        end
      end
    end

    def host_mode()
      if options[:host_mode]
        options[:host_mode]
      else
        HOST_MODE_DEFAULT
      end
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
      @optparse.on("--host-mode=MODE", "Specify custom host mode", Integer) do |v|
        options[:host_mode] = v.to_i
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
      @optparse.on("-x", "--display-search-tags", "Show tags used in search expression") do |v|
        options[:display_search_tags] = v
      end
      @optparse.on("-V", "--[no-]verbose", "Enable verbose mode") do |v|
        options[:verbose] = v
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
        library = find_library("hotdog/formatters", name)
        if library
          load library
          klass = Hotdog::Formatters.const_get(const_name(File.basename(library, ".rb")))
        else
          raise(NameError.new("unknown format: #{name}"))
        end
      end
      klass.new
    end

    def get_command(name)
      begin
        klass = Hotdog::Commands.const_get(const_name(name))
      rescue NameError
        library = find_library("hotdog/commands", name)
        if library
          load library
          klass = Hotdog::Commands.const_get(const_name(File.basename(library, ".rb")))
        else
          raise(NameError.new("unknown command: #{name}"))
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

    def update_api_key!()
      if options[:api_key_command]
        logger.info("api_key_command> #{options[:api_key_command]}")
        options[:api_key] = IO.popen(options[:api_key_command]) do |io|
          io.read.strip
        end
        unless $?.success?
          raise("failed: #{options[:api_key_command]}")
        end
      else
        update_keys!
      end
    end

    def update_application_key!()
      if options[:application_key_command]
        logger.info("application_key_command> #{options[:application_key_command]}")
        options[:application_key] = IO.popen(options[:application_key_command]) do |io|
          io.read.strip
        end
        unless $?.success?
          raise("failed: #{options[:application_key_command]}")
        end
      else
        update_keys!
      end
    end

    def update_keys!()
      if options[:key_command]
        logger.info("key_command> #{options[:key_command]}")
        options[:api_key], options[:application_key] = IO.popen(options[:key_command]) do |io|
          io.read.strip.split(":", 2)
        end
        unless $?.success?
          raise("failed: #{options[:key_command]}")
        end
      end
    end
  end
end

# vim:set ft=ruby :
