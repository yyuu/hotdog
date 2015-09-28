#!/usr/bin/env ruby

require "yaml"

module Hotdog
  module Formatters
    class Yaml < BaseFormatter
      def format(result, options={})
        result = prepare(result)
        if options[:headers] and options[:fields]
          result.unshift(options[:fields])
        end
        result.to_yaml
      end
    end
  end
end

# vim:set ft=ruby :
