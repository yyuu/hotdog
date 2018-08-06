#!/usr/bin/env ruby

module Hotdog
  module Sources
    class BaseSource
      def initialize(application)
        @application = application
        @logger = application.logger
        @options = application.options
      end
      attr_reader :application
      attr_reader :logger
      attr_reader :options

      def id()
        raise(NotImplementedError)
      end

      def name()
        raise(NotImplementedError)
      end

      def endpoint()
        options[:endpoint]
      end

      def api_key()
        options[:api_key]
      end

      def application_key()
        options[:application_key]
      end

      def schedule_downtime(*args)
        raise(NotImplementedError)
      end

      def cancel_downtime(*args)
        raise(NotImplementedError)
      end

      def get_all_downtimes()
        raise(NotImplementedError)
      end

      def get_all_tags()
        raise(NotImplementedError)
      end

      def get_host_tags()
        raise(NotImplementedError)
      end

      def add_tags(*args)
        raise(NotImplementedError)
      end

      def detach_tags(*args)
        raise(NotImplementedError)
      end

      def update_tags(*args)
        raise(NotImplementedError)
      end
    end
  end
end
