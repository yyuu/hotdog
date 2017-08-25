#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Tags < BaseCommand
      def run(args=[], options={})
        if args.empty?
          result = execute("SELECT name, value FROM tags").map { |name, value| [join_tag(name, value)] }
          show_tags(result)
        else
          tags = args.map { |tag| split_tag(tag) }
          sqlite_limit_compound_select = options[:sqlite_limit_compound_select] || SQLITE_LIMIT_COMPOUND_SELECT
          if tags.all? { |_tagname, tagvalue| tagvalue.empty? }
            result = tags.each_slice(sqlite_limit_compound_select).flat_map { |tags|
              q = "SELECT value FROM tags " \
                    "WHERE %s;" % tags.map { |tagname, _tagvalue| glob?(tagname) ? "LOWER(name) GLOB LOWER(?)" : "name = ?" }.join(" OR ")
              execute(q, tags.map { |tagname, _tagvalue| tagname }).map { |value| [value] }
            }
          else
            result = tags.each_slice(sqlite_limit_compound_select / 2).flat_map { |tags|
              q = "SELECT value FROM tags " \
                    "WHERE %s;" % tags.map { |tagname, tagvalue| (glob?(tagname) or glob?(tagvalue)) ? "( LOWER(name) GLOB LOWER(?) AND LOWER(value) GLOB LOWER(?) )" : "( name = ? AND value = ? )" }.join(" OR ")
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
