#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Tags < BaseCommand
      def run(args=[])
        args = optparse.parse(args)
        q = []
        if 0 < args.length
          fields = args.map { |tag|
            tag_name, tag_value = tag.split(":", 2)
            tag_name
          }
          result1 = fields.map { |tag_name|
            if not glob?(tag_name)
              q << "SELECT DISTINCT tags.value FROM hosts_tags"
              q <<   "INNER JOIN tags ON hosts_tags.tag_id = tags.id"
              q <<     "WHERE tags.name = ?;"
            else
              q << "SELECT DISTINCT tags.value FROM hosts_tags"
              q <<   "INNER JOIN tags ON hosts_tags.tag_id = tags.id"
              q <<     "WHERE tags.name GLOB ?;"
            end
            execute(q.join(" "), [tag_name]).map { |row| row.join(",") }
          }
          result = (0...result1.reduce(0) { |max, values| [max, values.length].max }).map { |field_index|
            result1.map { |values| values[field_index] }
          }
        else
          fields = ["tag"]
          q << "SELECT DISTINCT tags.name, tags.value FROM hosts_tags"
          q <<   "INNER JOIN tags ON hosts_tags.tag_id = tags.id;"
          result = execute(q.join(" ")).map { |name, value| [0 < value.length ? "#{name}:#{value}" : name] }
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
