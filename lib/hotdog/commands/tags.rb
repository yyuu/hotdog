#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Tags < BaseCommand
      def run(args=[])
        args = optparse.parse(args)
        if args.empty?
          result = execute("SELECT name, value FROM tags").map { |name, value| [join_tag(name, value)] }
          show_tags(result)
        else
          tags = args.map { |tag| split_tag(tag) }
          if tags.all? { |tag_name, tag_value| tag_value.empty? }
            result = tags.each_slice(SQLITE_LIMIT_COMPOUND_SELECT).flat_map { |tags|
              q = "SELECT value FROM tags " \
                    "WHERE %s;" % tags.map { |tag_name, tag_value| glob?(tag_name) ? "LOWER(name) GLOB LOWER(?)" : "name = ?" }.join(" OR ")
              execute(q, tags.map { |tag_name, tag_value| tag_name }).map { |value| [value] }
            }
          else
            result = tags.each_slice(SQLITE_LIMIT_COMPOUND_SELECT / 2).flat_map { |tags|
              q = "SELECT value FROM tags " \
                    "WHERE %s;" % tags.map { |tag_name, tag_value| (glob?(tag_name) or glob?(tag_value)) ?  "( LOWER(name) GLOB LOWER(?) AND LOWER(value) GLOB LOWER(?) )" : "( name = ? AND value = ? )" }.join(" OR ")
              execute(q, tags).map { |value| [value] }
            }
          end
          if result.empty?
            STDERR.puts("no match found: #{args.join(" ")}")
            exit(1)
          else
            show_tags(result)
            logger.info("found %d tag(s)." % result.length)
            if result.length < args.length
              STDERR.puts("insufficient result: #{args.join(" ")}")
              exit(1)
            end
          end
        end
      end

      def show_tags(tags)
        STDOUT.print(format(tags, fields: ["tag"]))
      end
    end
  end
end

# vim:set ft=ruby :
