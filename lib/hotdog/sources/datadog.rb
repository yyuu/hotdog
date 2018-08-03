#!/usr/bin/env ruby

require "dogapi"
require "multi_json"
require "oj"
require "open-uri"
require "uri"

module Hotdog
  module Sources
    class Datadog < BaseSource
      def initialize(application)
        super(application)
        options[:endpoint] = ENV.fetch("DATADOG_HOST", "https://app.datadoghq.com")
        options[:api_key] = ENV["DATADOG_API_KEY"]
        options[:application_key] = ENV["DATADOG_APPLICATION_KEY"]
        @dog = nil # lazy initialization
      end

      def id()
        Hotdog::SOURCE_DATADOG
      end

      def name()
        "datadog"
      end

      def endpoint()
        options[:endpoint]
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

      def schedule_downtime(scope, options={})
        code, schedule = dog.schedule_downtime(scope, :start => options[:start].to_i, :end => (options[:start]+options[:downtime]).to_i)
        logger.debug("dog.schedule_donwtime(%s, :start => %s, :end => %s) #==> [%s, %s]" % [scope.inspect, options[:start].to_i, (options[:start]+options[:downtime]).to_i, code.inspect, schedule.inspect])
        if code.to_i / 100 != 2
          raise("dog.schedule_downtime(%s, ...) returns [%s, %s]" % [scope.inspect, code.inspect, schedule.inspect])
        end
        schedule
      end

      def cancel_downtime(id, options={})
        code, cancel = dog.cancel_downtime(id)
        if code.to_i / 100 != 2
          raise("dog.cancel_downtime(%s) returns [%s, %s]" % [id.inspect, code.inspect, cancel.inspect])
        end
        cancel
      end

      def get_all_downtimes()
        prepare_downtimes(datadog_get("/api/v1/downtime"))
      end

      def get_all_tags()
        prepare_tags(datadog_get("/api/v1/tags/hosts"))
      end

      def get_host_tags(host_name, options={})
        code, host_tags = dog.host_tags(host_name, options)
        if code.to_i / 100 != 2
          raise("dog.host_tags(#{host_name.inspect}, #{options.inspect}) returns [#{code.inspect}, #{host_tags.inspect}]")
        end
        host_tags
      end

      def add_tags(*args)
        code, resp = dog.add_tags(host_name, tags, options)
        if code.to_i / 100 != 2
          raise("dog.add_tags(#{host_name.inspect}, #{tags.inspect}, #{options.inspect}) returns [#{code.inspect}, #{resp.inspect}]")
        end
        resp
      end

      def detach_tags(host_name, options={})
        code, detach_tags = dog.detach_tags(host_name, options)
        if code.to_i / 100 != 2
          raise("dog.detach_tags(#{host_name.inspect}, #{options.inspect}) returns [#{code.inspect}, #{detach_tags.inspect}]")
        end
        detach_tags
      end

      def update_tags(host_name, tags, options={})
        code, update_tags = dog.update_tags(host_name, tags, options)
        if code.to_i / 100 != 2
          raise("dog.update_tags(#{host_name.inspect}, #{tags.inspect}, #{options.inspect}) returns [#{code.inspect}, #{update_tags.inspect}]")
        end
        update_tags
      end

      private
      def dog()
        @dog ||= Dogapi::Client.new(self.api_key, self.application_key)
      end

      def datadog_get(request_path, query=nil)
        query ||= URI.encode_www_form(api_key: self.api_key, application_key: self.application_key)
        uri = URI.join(self.endpoint, "#{request_path}?#{query}")
        begin
          response = uri.open("User-Agent" => "hotdog/#{Hotdog::VERSION}") { |fp| fp.read }
          MultiJson.load(response)
        rescue OpenURI::HTTPError => error
          code, _body = error.io.status
          raise(RuntimeError.new("datadog: GET #{request_path} returns [#{code.inspect}, ...]"))
        end
      end

      def prepare_tags(tags)
        Hash(tags).fetch("tags", {})
      end

      def prepare_downtimes(downtimes)
        now = Time.new.to_i
        Array(downtimes).select { |downtime|
          # active downtimes
          downtime["active"] and ( downtime["start"].nil? or downtime["start"] < now ) and ( downtime["end"].nil? or now <= downtime["end"] ) and downtime["monitor_id"].nil?
        }.flat_map { |downtime|
          # find host scopes
          downtime["scope"].select { |scope| scope.start_with?("host:") }.map { |scope| scope.sub(/\Ahost:/, "") }
        }
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
end

# vim:set ft=ruby :
