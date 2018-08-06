#!/usr/bin/env ruby

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
        optparse.on("--tag-source SOURCE") do |v|
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
          # Try reloading database after error as a workaround for nested transaction.
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
              @source_provider.detach_tags(host, source=options[:tag_source])
            end
          else
            host_tags = with_retry { @source_provider.host_tags(host, source=options[:tag_source]) }
            old_tags = host_tags["tags"]
            new_tags = old_tags - options[:tags]
            if old_tags == new_tags
              # nop
            else
              with_retry do
                @source_provider.update_tags(host, new_tags, source=options[:tag_source])
              end
            end
          end
        end
      end
    end
  end
end

# vim:set ft=ruby :
