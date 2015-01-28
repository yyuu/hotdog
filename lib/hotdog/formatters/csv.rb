#!/usr/bin/env ruby

require "csv"

module Hotdog
  module Formatters
    class Csv < BaseFormatter
      def format(result, options={})
        result = result.dup
        if options[:headers] and options[:fields]
          result.unshift(options[:fields])
        end
        CSV.generate { |csv|
          result.each do |row|
            csv << row
          end
        }
      end
    end
  end
end

# vim:set ft=ruby :
