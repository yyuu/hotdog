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
              execute(<<-EOS, tag_name).map { |row| row.join(",") }
                SELECT DISTINCT tags.value FROM hosts_tags
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE tags.name = LOWER(?);
              EOS
            else
              execute(<<-EOS, tag_name).map { |row| row.join(",") }
                SELECT DISTINCT tags.value FROM hosts_tags
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE tags.name GLOB LOWER(?);
              EOS
            end
          }
          result = (0...result1.reduce(0) { |max, values| [max, values.length].max }).map { |field_index|
            result1.map { |values| values[field_index] }
          }
        else
          fields = ["tag"]
          result = execute(<<-EOS).map { |name, value| [0 < value.length ? "#{name}:#{value}" : name] }
            SELECT DISTINCT tags.name, tags.value FROM hosts_tags
              INNER JOIN tags ON hosts_tags.tag_id = tags.id;
          EOS
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
