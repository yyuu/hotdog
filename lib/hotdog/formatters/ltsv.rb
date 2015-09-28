#!/usr/bin/env ruby

module Hotdog
  module Formatters
    class Ltsv < BaseFormatter
      def format(result, options={})
        result = prepare(result)
        if options[:fields]
          result.map { |row|
            options[:fields].zip(row).map { |(field, column)|
              if column.empty?
                field.to_s
              else
                "#{field}:#{column}"
              end
            }.join("\t")
          }.join("\n") + "\n"
        else
          result.map { |row|
            row.join("\t")
          }.join("\n") + "\n"
        end
      end
    end
  end
end

# vim:set ft=ruby :
