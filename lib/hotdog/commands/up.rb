#!/usr/bin/env ruby

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
          all_downtimes = @source_provider.get_all_downtimes(options)
        end

        cancel_downtimes = all_downtimes.select { |downtime|
          downtime["active"] and downtime["id"] and scopes.map { |scope| downtime.fetch("scope", []).include?(scope) }.any?
        }

        cancel_downtimes.each do |downtime|
          with_retry(options) do
            @source_provider.cancel_downtime(downtime["id"], options)
          end
        end

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
                  execute_db(@db, "UPDATE hosts SET status = ? WHERE name IN (%s);" % hosts.map { "?" }.join(", "), [STATUS_RUNNING] + hosts)
                end
                associate_tag_hosts(@db, "@status:#{application.status_name(STATUS_RUNNING)}", hosts)
              end
            end
          end
        end
      end
    end
  end
end

# vim:set ft=ruby :
