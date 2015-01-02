#!/usr/bin/env ruby

require "json"

module Hotdog
  module Formatters
    class Json < BaseFormatter
      def format(result, options={})
        result = result.dup
        if options[:headers] and options[:fields]
          result.unshift(options[:fields])
        end
        JSON.pretty_generate(result) + "\n"
      end
    end
  end
end

# vim:set ft=ruby :
