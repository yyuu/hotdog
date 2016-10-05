#!/usr/bin/env ruby

require "fileutils"

module Hotdog
  module Commands
    class Untag < BaseCommand
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
            # delete all user tags
            code, detach_tags = dog.detach_tags(host_name, source="user")
            if code.to_i / 100 != 2
              raise("dog.detach_tags(#{host_name.inspect}, source=\"user\") returns [#{code.inspect}, #{detach_tags.inspect}]")
            end
          else
            code, host_tags = dog.host_tags(host_name, source="user")
            if code.to_i / 100 != 2
              raise("dog.host_tags(#{host_name.inspect}, source=\"user\") returns [#{code.inspect}, #{host_tags.inspect}]")
            end
            old_tags = host_tags["tags"]
            new_tags = old_tags - options[:tags]
            if old_tags == new_tags
              # nop
            else
              code, update_tags = dog.update_tags(host_name, new_tags, source="user")
              if code.to_i / 100 != 2
                raise("dog.update_tags(#{host_name.inspect}, #{new_tags.inspect}, source=\"user\") returns [#{code.inspect}, #{update_tags.inspect}]")
              end
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
