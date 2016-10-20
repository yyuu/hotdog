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
        args.each do |host_name|
          host_name = host_name.sub(/\Ahost:/, "")

          if options[:tags].empty?
            # nop
          else
            # add all as user tags
            with_retry(options) do
              add_tags(host_name, options[:tags], source=options[:tag_source])
            end
          end
        end

        # Remove persistent.db to schedule update on next invocation
        if @db
          close_db(@db)
        end
        FileUtils.rm_f(File.join(options[:confdir], PERSISTENT_DB))
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
