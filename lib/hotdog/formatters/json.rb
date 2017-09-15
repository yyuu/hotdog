#!/usr/bin/env ruby

require "json"

module Hotdog
  module Formatters
    class Json < BaseFormatter
      def format(result, options={})
        result = prepare(result)
        if options[:headers] and options[:fields]
          result.map! do |record|
            Hash[options[:fields].zip(record)]
          end
          JSON.pretty_generate(result) + newline
        else
          JSON.pretty_generate(result) + newline
        end
      end
    end
  end
end

# vim:set ft=ruby :
