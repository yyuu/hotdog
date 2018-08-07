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

      def id() #=> Integer
        raise(NotImplementedError)
      end

      def name() #=> String
        raise(NotImplementedError)
      end

      def endpoint() #=> String
        options[:endpoint]
      end

      def api_key() #=> String
        options[:api_key]
      end

      def application_key() #=> String
        options[:application_key]
      end

      def schedule_downtime(scope, options={})
        raise(NotImplementedError)
      end

      def cancel_downtime(id, options={})
        raise(NotImplementedError)
      end

      def get_all_downtimes(options={})
        #
        # This should return some `Array<Hash<String,String>>` like follows
        #
        # ```json
        # [
        #   {
        #     "recurrence": null,
        #     "end": 1533593208,
        #     "monitor_tags": [
        #       "*"
        #     ],
        #     "canceled": null,
        #     "monitor_id": null,
        #     "org_id": 12345,
        #     "disabled": false,
        #     "start": 1533592608,
        #     "creator_id": 78913,
        #     "parent_id": null,
        #     "timezone": "UTC",
        #     "active": false,
        #     "scope": [
        #       "host:i-abcdef01234567890"
        #     ],
        #     "message": null,
        #     "downtime_type": null,
        #     "id": 278432422,
        #     "updater_id": null
        #   }
        # ]
        # ```
        #
        raise(NotImplementedError)
      end

      def get_all_tags(options={})
        #
        # This should return some `Hash<String,Hash<String,Array<String>>>` like follows
        #
        # ```json
        # {
        #  "tags": {
        #    "tagname:tagvalue": [
        #      "foo"
        #    ]
        #  }
        #}
        # ```
        #
        raise(NotImplementedError)
      end

      def get_host_tags(host_name, options={})
        raise(NotImplementedError)
      end

      def add_tags(host_name, tags, options={})
        raise(NotImplementedError)
      end

      def detach_tags(host_name, options={})
        raise(NotImplementedError)
      end

      def update_tags(host_name, tags, options={})
        raise(NotImplementedError)
      end
    end
  end
end
