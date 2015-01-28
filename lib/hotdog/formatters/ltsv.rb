#!/usr/bin/env ruby

module Hotdog
  module Formatters
    class Ltsv < BaseFormatter
      def format(result, options={})
        fields = options.fetch(:fields, [])
        result.map { |row|
          fields.zip(row).map { |column| column.join(":") }.join("\t")
        }.join("\n") + "\n"
      end
    end
  end
end

# vim:set ft=ruby :
