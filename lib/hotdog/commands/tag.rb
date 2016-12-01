#!/usr/bin/env ruby

require "fileutils"

module Hotdog
  module Commands
    class Tag < BaseCommand
      def define_options(optparse, options={})
        default_option(options, :retry, 5)
        default_option(options, :tag_source, "user")
        default_option(options, :tags, [])
        optparse.on("--retry NUM") do |v|
          options[:retry] = v.to_i
        end
        optparse.on("--retry-delay SECONDS") do |v|
          options[:retry_delay] = v.to_i
        end
        optparse.on("--source SOURCE") do |v|
          options[:tag_source] = v
        end
        optparse.on("-a TAG", "-t TAG", "--tag TAG", "Use specified tag name/value") do |v|
          options[:tags] << v
        end
      end

      def run(args=[], options={})
        hosts = args.map { |arg|
          arg.sub(/\Ahost:/, "")
        }
        hosts.each do |host|
          if options[:tags].empty?
            # nop
          else
            # add all as user tags
            with_retry(options) do
              add_tags(host, options[:tags], source=options[:tag_source])
            end
          end
        end
        if open_db
          options[:tags].each do |tag|
            execute_db(@db, "INSERT OR IGNORE INTO tags (name, value) VALUES (?, ?)", split_tag(tag))
            q = "INSERT OR REPLACE INTO hosts_tags (host_id, tag_id) " \
                  "SELECT host.id, tag.id FROM " \
                    "( SELECT id FROM hosts WHERE name IN (%s) ) AS host, " \
                    "( SELECT id FROM tags WHERE name = ? AND value = ? LIMIT 1 ) AS tag;" % hosts.map { "?" }.join(", ")
            execute_db(@db, q, (hosts + split_tag(tag)))
          end
        end
      end

      private
      def add_tags(host_name, tags, options={})
        code, resp = dog.add_tags(host_name, tags, options)
        if code.to_i / 100 != 2
          raise("dog.add_tags(#{host_name.inspect}, #{tags.inspect}, #{options.inspect}) returns [#{code.inspect}, #{resp.inspect}]")
        end
        resp
      end
    end
  end
end

# vim:set ft=ruby :
