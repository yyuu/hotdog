#!/usr/bin/env ruby

require "fileutils"

module Hotdog
  module Commands
    class Down < BaseCommand
      def define_options(optparse, options={})
        default_option(options, :downtime, 86400)
        default_option(options, :start, Time.new)
        default_option(options, :retry, 5)
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
        args.each do |arg|
          if arg.index(":").nil?
            scope = "host:#{arg}"
          else
            scope = arg
          end
          if 0 < options[:retry]
            options[:retry].times do |i|
              begin
                schedule_downtime(scope, options)
                break
              rescue => error
                logger.warn(error.to_s)
                sleep(options[:retry_delay] || (1<<i))
              end
            end
          else
            schedule_downtime(scope, options)
          end
        end

        # Remove persistent.db to schedule update on next invocation
        if @db
          close_db(@db)
        end
        FileUtils.rm_f(File.join(options[:confdir], PERSISTENT_DB))
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
