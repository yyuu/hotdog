#!/usr/bin/env ruby

require "json"

module Hotdog
  module Formatters
    class Json < BaseFormatter
      def format(result, options={})
        JSON.pretty_generate(result) + "\n"
      end
    end
  end
end

# vim:set ft=ruby :
