#!/usr/bin/env ruby

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
        # Try reloading database after error as a workaround for nested transaction.
        with_retry(error_handler: ->(error) { reload }) do
          if open_db
            @db.transaction do
              create_tags(@db, options[:tags])
              options[:tags].each do |tag|
                associate_tag_hosts(@db, tag, hosts)
              end
            end
          end
        end
        hosts.each do |host|
          if options[:tags].empty?
            # nop; just show current tags
            host_tags = with_retry { @source_provider.host_tags(host, source=options[:tag_source]) }
            STDOUT.puts host_tags['tags'].inspect
          else
            # add all as user tags
            with_retry(options) do
              @source_provider.add_tags(host, options[:tags], source=options[:tag_source])
            end
          end
        end
      end
    end
  end
end

# vim:set ft=ruby :
