#!/usr/bin/env ruby

require "fileutils"

module Hotdog
  module Commands
    class Up < BaseCommand
      def define_options(optparse, options={})
        default_option(options, :retry, 5)
        optparse.on("--retry NUM") do |v|
          options[:retry] = v.to_i
        end
        optparse.on("--retry-delay SECONDS") do |v|
          options[:retry_delay] = v.to_i
        end
      end

      def run(args=[], options={})
        scopes = args.map { |arg|
          if arg.index(":").nil?
            "host:#{arg}"
          else
            arg
          end
        }
        all_downtimes = nil
        with_retry(options) do
          all_downtimes = get_all_downtimes(options)
        end

        cancel_downtimes = all_downtimes.select { |downtime|
          downtime["active"] and downtime["id"] and scopes.map { |scope| downtime.fetch("scope", []).include?(scope) }.any?
        }

        cancel_downtimes.each do |downtime|
          with_retry(options) do
            cancel_downtime(downtime["id"], options)
          end
        end

        # Remove persistent.db to schedule update on next invocation
        if @db
          close_db(@db)
        end
        FileUtils.rm_f(File.join(options[:confdir], PERSISTENT_DB))
      end

      private
      def get_all_downtimes(options={})
        code, all_downtimes = dog.get_all_downtimes()
        if code.to_i / 100 != 2
          raise("dog.get_all_downtimes() returns [%s, %s]" % [code.inspect, all_downtimes.inspect])
        end
        all_downtimes
      end

      def cancel_downtime(id, options={})
        code, cancel = dog.cancel_downtime(id)
        if code.to_i / 100 != 2
          raise("dog.cancel_downtime(%s) returns [%s, %s]" % [id.inspect, code.inspect, cancel.inspect])
        end
        cancel
      end
    end
  end
end

# vim:set ft=ruby :
