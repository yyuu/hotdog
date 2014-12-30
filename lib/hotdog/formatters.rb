#!/usr/bin/env ruby

module Hotdog
  module Formatters
    class BaseFormatter
      def format(result, options={})
        raise(NotImplementedError)
      end
    end
  end
end

# vim:set ft=ruby :
