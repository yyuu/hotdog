#!/usr/bin/env ruby

require "fileutils"

module Hotdog
  module Commands
    class Tag < BaseCommand
      def define_options(optparse, options={})
        default_option(options, :tags, [])
        optparse.on("--tag TAG") do |v|
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
            code, add_tags = dog.add_tags(host_name, options[:tags], source="user")
            if code.to_i / 100 != 2
              raise("dog.add_tags(#{host_name.inspect}, #{options[:tags].inspect}, source=\"user\") returns [#{code.inspect}, #{add_tags.inspect}]")
            end
          end
        end

        # Remove persistent.db to schedule update on next invocation
        if @db
          close_db(@db)
        end
        FileUtils.rm_f(File.join(options[:confdir], PERSISTENT_DB))
      end
    end
  end
end

# vim:set ft=ruby :
