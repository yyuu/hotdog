#!/usr/bin/env ruby

require "fileutils"

module Hotdog
  module Commands
    class Down < BaseCommand
      def run(args=[])
        if args.index("--start").nil?
          start = Time.new
        else
          start = Time.parse(args[args.index("--start") + 1])
          args.slice!(args.index("--start"), 2)
        end
        if args.index("--downtime").nil?
          downtime = 86400
        else
          downtime = args[args.index("--downtime") + 1].to_i
          args.slice!(args.index("--downtime"), 2)
        end

        args.each do |arg|
          if arg.index(":").nil?
            scope = "host:#{arg}"
          else
            scope = arg
          end
          code, schedule = @dog.schedule_downtime(scope, :start => start.to_i, :end => (start+downtime).to_i)
          logger.debug("dog.schedule_donwtime(%s, :start => %s, :end => %s) #==> [%s, %s]" % [scope.inspect, start.to_i, (start+downtime).to_i, code.inspect, schedule.inspect])
          if code.to_i / 100 != 2
            raise("dog.schedule_downtime(%s, ...) returns [%s, %s]" % [scope.inspect, code.inspect, schedule.inspect])
          end
        end

        # Remove persistent.db to schedule update on next invocation
        if not @db.nil?
          @db.close
          FileUtils.rm_f(File.join(confdir, PERSISTENT_DB))
        end
      end
    end
  end
end

# vim:set ft=ruby :
