#!/usr/bin/env ruby

require "json"
require "parslet"
require "shellwords"
require "hotdog/expression"

module Hotdog
  module Commands
    class Search < BaseCommand
      def define_options(optparse, options={})
        optparse.on("-n", "--limit LIMIT", "Limit result set to specified size at most", Integer) do |limit|
          options[:limit] = limit
        end
      end

      def parse_options(optparse, args=[])
        if args.index("--")
          command_args = args.slice(args.index("--") + 1, args.length)
          if command_args.length <= 1
            # Use given argument as is if the remote command is specified as a quoted string
            # e.g. 'for f in /tmp/foo*; do echo $f; done'
            @remote_command = command_args.first
          else
            @remote_command = Shellwords.shelljoin(command_args)
          end
          optparse.parse(args.slice(0, args.index("--")))
        else
          @remote_command = nil
          optparse.parse(args)
        end
      end
      attr_reader :remote_command

      def run(args=[], options={})
        if @remote_command
          logger.warn("ignore remote command: #{@remote_command}")
        end
        expression = args.join(" ").strip
        if expression.empty?
          # return everything if given expression is empty
          expression = "*"
        end

        begin
          node = parse(expression)
        rescue Parslet::ParseFailed => error
          STDERR.puts("syntax error: " + error.cause.ascii_tree)
          exit(1)
        end

        result0 = evaluate(node, self)
        if 0 < result0.length
          result, fields = get_hosts_with_search_tags(result0, node)
          if options[:limit]
            STDOUT.print(format(result.take(options[:limit]), fields: fields))
            logger.info("found %d host(s), limited to %d in result." % [result.length, options[:limit]])
          else
            STDOUT.print(format(result, fields: fields))
            logger.info("found %d host(s)." % result.length)
          end
        else
          STDERR.puts("no match found: #{expression}")
          exit(1)
        end
      end

      def get_hosts_with_search_tags(result, node)
        drilldown = ->(n) {
          case
          when n[:left] && n[:right] then drilldown.(n[:left]) + drilldown.(n[:right])
          when n[:expression] then drilldown.(n[:expression])
          when n[:tag_name] then [n[:tag_name]]
          else []
          end
        }
        if options[:display_search_tags]
          tag_names = drilldown.call(node).map(&:to_s)
          if options[:primary_tag]
            tags = [options[:primary_tag]] + tag_names
          else
            tags = tag_names
          end
        else
          tags = nil
        end
        get_hosts(result, tags)
      end

      def parse(expression)
        logger.debug(expression)
        parser = Hotdog::Expression::ExpressionParser.new
        parser.parse(expression).tap do |parsed|
          logger.debug {
            begin
              JSON.pretty_generate(JSON.load(parsed.to_json))
            rescue JSON::NestingError => error
              error.message
            end
          }
        end
      end

      def evaluate(data, environment)
        node = Hotdog::Expression::ExpressionTransformer.new.apply(data)
        if Hotdog::Expression::ExpressionNode === node
          optimized = node.optimize.tap do |optimized|
            logger.debug {
              JSON.pretty_generate(optimized.dump)
            }
          end
          optimized.evaluate(environment)
        else
          raise("parser error: unknown expression: #{node.inspect}")
        end
      end
    end
  end
end

# vim:set ft=ruby :
