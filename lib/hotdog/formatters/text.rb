#!/usr/bin/env ruby

module Hotdog
  module Formatters
    class Text < BaseFormatter
      def format(result, options={})
        if options[:print0]
          sep = "\0"
          show_headers = false
        elsif options[:print1]
          sep = newline
          show_headers = true
        elsif options[:print2]
          sep = " "
          show_headers = true
        else
          sep = " "
          show_headers = true
        end
        result = prepare(result)
        if show_headers and options[:headers] and options[:fields]
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
              padding = length - ((field.nil?) ? 0 : field.to_s.length)
              field.to_s + (" " * padding)
            }
          }
        end
        s = _format(result, sep, options)
        if s.empty? or options[:print0]
          s
        else
          s + newline
        end
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
