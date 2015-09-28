#!/usr/bin/env ruby

module Hotdog
  module Formatters
    class Tsv < BaseFormatter
      def format(result, options={})
        result = prepare(result)
        if options[:headers] and options[:fields]
          result.unshift(options[:fields])
        end
        result.map { |row|
          row.join("\t")
        }.join("\n") + "\n"
      end
    end
  end
end

# vim:set ft=ruby :
