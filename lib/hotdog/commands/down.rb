#!/usr/bin/env ruby

require "fileutils"

module Hotdog
  module Commands
    class Down < BaseCommand
      def define_options(optparse, options={})
        default_option(options, :downtime, 86400)
        default_option(options, :retry, 5)
        default_option(options, :start, Time.new)
        optparse.on("--downtime DURATION") do |v|
          options[:downtime] = v.to_i
        end
        optparse.on("--retry NUM") do |v|
          options[:retry] = v.to_i
        end
        optparse.on("--retry-delay SECONDS") do |v|
          options[:retry_delay] = v.to_i
        end
        optparse.on("--start TIME") do |v|
          options[:start] = Time.parse(v)
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
        scopes.each do |scope|
          with_retry(options) do
            schedule_downtime(scope, options)
          end
        end
        hosts = scopes.select { |scope| scope.start_with?("host:") }.map { |scope|
          scope.slice("host:".length, scope.length)
        }
        if 0 < hosts.length
          if open_db
            hosts.each_slice(SQLITE_LIMIT_COMPOUNT_SELECT - 2) do |hosts|
              execute_db(@db, "DELETE FROM hosts_tags WHERE host_id IN ( SELECT id FROM hosts WHERE name IN (%s) )" % hosts.map { "?" }.join(", "), hosts)
              execute_db(@db, "DELETE FROM hosts WHERE name IN (%s)" % hosts.map { "?" }.join(", "), hosts)
            end
          end
        end
      end

      private
      def schedule_downtime(scope, options={})
        code, schedule = dog.schedule_downtime(scope, :start => options[:start].to_i, :end => (options[:start]+options[:downtime]).to_i)
        logger.debug("dog.schedule_donwtime(%s, :start => %s, :end => %s) #==> [%s, %s]" % [scope.inspect, options[:start].to_i, (options[:start]+options[:downtime]).to_i, code.inspect, schedule.inspect])
        if code.to_i / 100 != 2
          raise("dog.schedule_downtime(%s, ...) returns [%s, %s]" % [scope.inspect, code.inspect, schedule.inspect])
        end
        schedule
      end
    end
  end
end

# vim:set ft=ruby :
