#!/usr/bin/env ruby

module Hotdog
  module Formatters
    class BaseFormatter
      def format(result, options={})
        raise(NotImplementedError)
      end

      private
      def prepare(result)
        result.map { |row| row.map { |column| column or "<nil>" } }
      end
    end
  end
end

# vim:set ft=ruby :
