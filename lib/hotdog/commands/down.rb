#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Down < BaseCommand
      def define_options(optparse, options={})
        default_option(options, :downtime, 86400)
        default_option(options, :retry, 5)
        default_option(options, :start, Time.new)
        optparse.on("--downtime DURATION") do |v|
          case v
          when /\A\s*(\d+)\s*(?:seconds?|sec|S)\s*\z/
            options[:downtime] = $1.to_i
          when /\A\s*(\d+)\s*(?:minutes?|min|M)\s*\z/
            options[:downtime] = $1.to_i * 60
          when /\A\s*(\d+)\s*(?:hours?|H)\s*\z/
            options[:downtime] = $1.to_i * 60 * 60
          when /\A\s*(\d+)\s*(?:days?|d)\s*\z/
            options[:downtime] = $1.to_i * 60 * 60 * 24
          when /\A\s*(\d+)\s*(?:weeks?|w)\s*\z/
            options[:downtime] = $1.to_i * 60 * 60 * 24 * 7
          when /\A\s*(\d+)\s*(?:months?|m)\s*\z/i
            options[:downtime] = $1.to_i * 60 * 60 * 24 * 30
          when /\A\s*(\d+)\s*(?:years?|y)\s*\z/i
            options[:downtime] = $1.to_i * 60 * 60 * 24 * 365
          when /\A\s*(\d+)\s*\z/
            options[:downtime] = $1.to_i
          else
            raise(OptionParser::InvalidArgument.new("downtime argument value is invalid: #{v}"))
          end
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
                  execute_db(@db, "DELETE FROM hosts_tags WHERE tag_id IN ( SELECT id FROM tags WHERE name = '@status' ) AND host_id IN ( SELECT id FROM hosts WHERE name IN (%s) );" % hosts.map { "?" }.join(", "), hosts)
                  execute_db(@db, "UPDATE hosts SET status = ? WHERE name IN (%s);" % hosts.map { "?" }.join(", "), [STATUS_STOPPING] + hosts)
                end
                associate_tag_hosts(@db, "@status:#{application.status_name(STATUS_STOPPING)}", hosts)
              end
            end
          end
        end
        scopes.each do |scope|
          with_retry(options) do
            @source_provider.schedule_downtime(scope, options)
          end
        end
      end
    end
  end
end

# vim:set ft=ruby :
