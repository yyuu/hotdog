#!/usr/bin/env ruby

module Hotdog
  module Formatters
    class Ltsv < BaseFormatter
      def format(result, options={})
        result = prepare(result)
        if options[:fields]
          result.map { |row|
            options[:fields].zip(row).map { |(field, column)|
              "#{field}:#{column}"
            }.join("\t")
          }.join(newline) + newline
        else
          result.map { |row|
            row.join("\t")
          }.join(newline) + newline
        end
      end
    end
  end
end

# vim:set ft=ruby :
