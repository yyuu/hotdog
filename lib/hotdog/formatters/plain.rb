#!/usr/bin/env ruby

module Hotdog
  module Formatters
    class Plain < BaseFormatter
      def format(result, options={})
        if options[:print0]
          sep = "\0"
        elsif options[:print1]
          sep = "\n"
        else
          sep = " "
        end
        if options[:print1] and options[:headers] and options[:fields]
          field_length = (0...result.last.length).map { |field_index|
            result.reduce(0) { |length, row|
              [length, row[field_index].to_s.length, options[:fields][field_index].to_s.length].max
            }
          }
          header_fields = options[:fields].zip(field_length).map { |field, length|
            field.to_s + (" " * (length - field.length))
          }
          result = [
            header_fields,
            header_fields.map { |field|
              "-" * field.length
            },
          ] + result.map { |row|
            row.zip(field_length).map { |field, length|
              field.to_s + (" " * (length - field.length))
            }
          }
        end
        _format(result, sep, options) + (options[:print0] ? "" : "\n")
      end

      def _format(result, sep, options={})
        result.map { |row|
          row.join(" ")
        }.join(sep)
      end
    end
  end
end

# vim:set ft=ruby :
