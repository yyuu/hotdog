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
        hosts = scopes.select { |scope| scope.start_with?("host:") }.map { |scope|
          scope.slice("host:".length, scope.length)
        }
        if 0 < hosts.length
          # Try reloading database after error as a workaround for nested transaction.
          with_retry(error_handler: ->(error) { reload }) do
            if open_db
              @db.transaction do
                sqlite_limit_compound_select = options[:sqlite_limit_compound_select] || SQLITE_LIMIT_COMPOUND_SELECT
                hosts.each_slice(sqlite_limit_compound_select - 1) do |hosts|
                  q = "UPDATE hosts SET status = ? WHERE name IN (%s);" % hosts.map { "?" }.join(", ")
                  execute_db(@db, q, [STATUS_STOPPING] + hosts)
                end
              end
            end
          end
        end
        scopes.each do |scope|
          with_retry(options) do
            schedule_downtime(scope, options)
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
