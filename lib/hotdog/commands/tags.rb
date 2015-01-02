#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Tags < BaseCommand
      def run(args=[])
        application.run_command("init")
        update_tags(@options.dup)
        if 0 < tags.length
          fields = tags.map { |tag|
            tag_name, tag_value = tag.split(":", 2)
            tag_name
          }
          result1 = fields.map { |tag_name|
            if not glob?(tag_name)
              @tags_q1 ||= @db.prepare(<<-EOS)
                SELECT DISTINCT tags.value FROM hosts_tags
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE tags.name = LOWER(?);
              EOS
              logger.debug("tags_q1(%s)" % [tag_name.inspect])
              @tags_q1.execute(tag_name).map { |row| row.join(",") }
            else
              @tags_q2 ||= @db.prepare(<<-EOS)
                SELECT DISTINCT tags.value FROM hosts_tags
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE tags.name GLOB LOWER(?);
              EOS
              logger.debug("tags_q2(%s)" % [tag_name.inspect])
              @tags_q2.execute(tag_name).map { |row| row.join(",") }
            end
          }
          result = (0..result1.reduce(0) { |max, values| [max, values.length].max }).map { |field_index|
            result1.map { |values| values[field_index] }
          }
        else
          fields = ["tag"]
          @tags_q3 ||= @db.prepare(<<-EOS)
            SELECT tags.name, tags.value FROM hosts_tags
              INNER JOIN tags ON hosts_tags.tag_id = tags.id;
          EOS
          logger.debug("tags_q3()")
          result = @tags_q3.execute().map { |name, value| [0 < value.length ? "#{name}:#{value}" : name] }
        end
        if 0 < result.length
          STDOUT.print(format(result, fields: fields))
          logger.debug("found %d tag(s)." % result.length)
        end
      end
    end
  end
end

# vim:set ft=ruby :
