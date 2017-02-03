#!/usr/bin/env ruby

require "fileutils"

module Hotdog
  module Commands
    class Untag < BaseCommand
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

        if options[:tags].empty?
          # refresh all persistent.db since there is no way to identify user tags
          remove_db(@db)
        else
          with_retry(error_handler: -> (error) { reload }) do
            if open_db
              @db.transaction do
                options[:tags].each do |tag|
                  disassociate_tag_hosts(@db, tag, hosts)
                end
              end
            end
          end
        end

        hosts.each do |host|
          if options[:tags].empty?
            # delete all user tags
            with_retry do
              detach_tags(host, source=options[:tag_source])
            end
          else
            host_tags = with_retry { host_tags(host, source=options[:tag_source]) }
            old_tags = host_tags["tags"]
            new_tags = old_tags - options[:tags]
            if old_tags == new_tags
              # nop
            else
              with_retry do
                update_tags(host, new_tags, source=options[:tag_source])
              end
            end
          end
        end
      end

      private
      def detach_tags(host_name, options={})
        code, detach_tags = dog.detach_tags(host_name, options)
        if code.to_i / 100 != 2
          raise("dog.detach_tags(#{host_name.inspect}, #{options.inspect}) returns [#{code.inspect}, #{detach_tags.inspect}]")
        end
        detach_tags
      end

      def host_tags(host_name, options={})
        code, host_tags = dog.host_tags(host_name, options)
        if code.to_i / 100 != 2
          raise("dog.host_tags(#{host_name.inspect}, #{options.inspect}) returns [#{code.inspect}, #{host_tags.inspect}]")
        end
        host_tags
      end

      def update_tags(host_name, tags, options={})
        code, update_tags = dog.update_tags(host_name, tags, options)
        if code.to_i / 100 != 2
          raise("dog.update_tags(#{host_name.inspect}, #{tags.inspect}, #{options.inspect}) returns [#{code.inspect}, #{update_tags.inspect}]")
        end
        update_tags
      end
    end
  end
end

# vim:set ft=ruby :
