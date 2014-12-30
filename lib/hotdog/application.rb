#!/usr/bin/env ruby

require "logger"
require "optparse"
require "shellwords"
require "sqlite3"
require "hotdog/commands"
require "hotdog/formatters"

module Hotdog
  class Application
    def initialize()
      @confdir = File.join(ENV["HOME"], ".hotdog")
      @optparse = OptionParser.new
      @options = {
        environment: "default",
        minimum_expiry: 28800, # 8 hours
        random_expiry: 57600, # 16 hours
        force: false,
        formatter: get_formatter("plain").new,
        headers: false,
        listing: false,
        logger: Logger.new(STDERR),
        api_key: ENV["DATADOG_API_KEY"],
        application_key: ENV["DATADOG_APPLICATION_KEY"],
        print0: false,
        print1: true,
        tags: [],
      }
      @options[:logger].level = Logger::INFO
      define_options
    end
    attr_reader :options

    def main(argv=[])
      config = File.join(@confdir, "config.yml")
      if File.file?(config)
        @options = @options.merge(YAML.load(File.read(config)))
      end
      args = @optparse.parse(argv)

      unless options[:api_key]
        raise("DATADOG_API_KEY is not set")
      end

      unless options[:application_key]
        raise("DATADOG_APPLICATION_KEY is not set")
      end

      sqlite = File.expand_path(File.join(@confdir, "#{options[:environment]}.db"))
      FileUtils.mkdir_p(File.dirname(sqlite))
      @db = SQLite3::Database.new(sqlite)
      @db.synchronous = "off"

      begin
        command = ( args.shift || "help" )
        run_command(command, args)
      rescue Errno::EPIPE
        # nop
      end
    end

    def run_command(command, args=[])
      get_command(command).new(@db, options.merge(application: self)).run(args)
    end

    private
    def define_options
      @optparse.on("--api-key API_KEY") do |api_key|
        options[:api_key] = api_key
      end
      @optparse.on("--application-key APP_KEY") do |app_key|
        options[:application_key] = app_key
      end
      @optparse.on("-0", "--null") do
        options[:print0] = true
      end
      @optparse.on("-1") do
        options[:print1] = true
      end
      @optparse.on("-d", "--debug") do
        options[:logger].level = Logger::DEBUG
      end
      @optparse.on("-E ENVIRONMENT", "--environment ENVIRONMENT") do |environment|
        options[:environment] = environment
      end
      @optparse.on("-f", "--force") do
        options[:force] = true
      end
      @optparse.on("-F FORMAT", "--format FORMAT") do |format|
        options[:formatter] = get_formatter(format).new
      end
      @optparse.on("-h", "--headers") do |headers|
        options[:headers] = headers
      end
      @optparse.on("-l") do
        options[:listing] = true
      end
      @optparse.on("-a TAG", "-t TAG", "--tag TAG") do |tag|
        options[:tags] += [tag]
      end
      @optparse.on("-V", "--verbose") do |tag|
        options[:logger].level = Logger::DEBUG
      end
    end

    def const_name(name)
      name.to_s.split(/[^\w]+/).map { |s| s.capitalize }.join
    end

    def get_formatter(name)
      begin
        Hotdog::Formatters.const_get(const_name(name))
      rescue NameError
        if library = find_library("hotdog/formatters", name)
          load library
          Hotdog::Formatters.const_get(const_name(File.basename(library, ".rb")))
        else
          raise(NameError.new("unknown format: #{name}"))
        end
      end
    end

    def get_command(name)
      begin
        Hotdog::Commands.const_get(const_name(name))
      rescue NameError
        if library = find_library("hotdog/commands", name)
          load library
          Hotdog::Commands.const_get(const_name(File.basename(library, ".rb")))
        else
          raise(NameError.new("unknown command: #{name}"))
        end
      end
    end

    def find_library(dirname, name)
      load_path = $LOAD_PATH.map { |path| File.join(path, dirname) }.select { |path| File.directory?(path) }
      libraries = load_path.map { |path| Dir.glob(File.join(path, "*.rb")) }.reduce(:+).select { |file| File.file?(file) }
      rbname = "#{name}.rb"
      if library = libraries.find { |file| File.basename(file) == rbname }
        library
      else
        candidates = libraries.map { |file| [file, File.basename(file).slice(0, name.length)] }.select { |file, s| s == name }
        if candidates.length == 1
          candidates.first.first
        else
          nil
        end
      end
    end
  end
end

# vim:set ft=ruby :
