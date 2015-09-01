#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Tags < BaseCommand
      def run(args=[])
        args = optparse.parse(args)
        if 0 < args.length
          fields = args.map { |tag|
            tag_name, tag_value = tag.split(":", 2)
            tag_name
          }
          result1 = fields.map { |tag_name|
            if not glob?(tag_name)
              execute("SELECT DISTINCT value FROM tags WHERE name = ?", [tag_name]).map { |row| row.join(",") }
            else
              execute("SELECT DISTINCT value FROM tags WHERE name GLOB ?", [tag_name]).map { |row| row.join(",") }
            end
          }
          result = (0...result1.reduce(0) { |max, values| [max, values.length].max }).map { |field_index|
            result1.map { |values| values[field_index] }
          }
        else
          fields = ["tag"]
          result = execute("SELECT DISTINCT name, value FROM tags").map { |name, value| [0 < value.length ? "#{name}:#{value}" : name] }
        end
        if 0 < result.length
          STDOUT.print(format(result, fields: fields))
          logger.info("found %d tag(s)." % result.length)
        end
      end
    end
  end
end

# vim:set ft=ruby :
