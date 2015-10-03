#!/usr/bin/env ruby

require "fileutils"

module Hotdog
  module Commands
    class Up < BaseCommand
      def run(args=[], options={})
        scopes = args.map { |arg|
          if arg.index(":").nil?
            "host:#{arg}"
          else
            arg
          end
        }
        code, all_downtimes = dog.get_all_downtimes()
        if code.to_i / 100 != 2
          raise("dog.get_all_downtimes() returns [%s, %s]" % [code.inspect, all_downtimes.inspect])
        end

        cancel_downtimes = all_downtimes.select { |downtime|
          downtime["active"] and downtime["id"] and scopes.map { |scope| downtime.fetch("scope", []).include?(scope) }.any?
        }

        cancel_downtimes.each do |downtime|
          code, cancel = dog.cancel_downtime(downtime["id"])
          if code.to_i / 100 != 2
            raise("dog.cancel_downtime(%s) returns [%s, %s]" % [downtime["id"].inspect, code.inspect, cancel.inspect])
          end
        end

        # Remove persistent.db to schedule update on next invocation
        if @db
          close_db(@db)
          FileUtils.rm_f(File.join(options[:confdir], PERSISTENT_DB))
        end
      end
    end
  end
end

# vim:set ft=ruby :
