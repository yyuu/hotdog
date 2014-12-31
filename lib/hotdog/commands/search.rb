#!/usr/bin/env ruby

require "json"
require "parslet"

module Hotdog
  module Commands
    class Search < BaseCommand
      def run(args=[])
        expression = args.join(" ").strip
        if expression.empty?
          exit(1)
        end

        update_hosts(@options.dup)

        begin
          node = parse(expression)
        rescue Parslet::ParseFailed => error
          STDERR.puts("syntax error: " + error.cause.ascii_tree)
          exit(1)
        end
        result = evaluate(node, self).sort
        if 0 < result.length
          result, fields = get_hosts(result)
          STDOUT.print(format(result, fields: fields))
        else
          STDERR.puts("no match found: #{args.join(" ")}")
          exit(1)
        end
      end

      def parse(expression)
        parser = ExpressionParser.new
        parser.parse(expression).tap do |parsed|
          logger.debug(JSON.pretty_generate(JSON.load(parsed.to_json)))
        end
      end

      def evaluate(node, environment)
        node = ExpressionTransformer.new.apply(node)
        node.evaluate(environment)
      end

      class ExpressionParser < Parslet::Parser
        root(:expression)
        rule(:expression) {
          ( binary_expression \
          | term \
          )
        }
        rule(:binary_expression) {
          ( term.as(:left) >> spacing.maybe >> (str('&') >> str('&').maybe).as(:binary_op) >> spacing.maybe >> expression.as(:right) \
          | term.as(:left) >> spacing.maybe >> (str('|') >> str('|').maybe).as(:binary_op) >> spacing.maybe >> expression.as(:right) \
          | term.as(:left) >> spacing.maybe >> (match('[Aa]') >> match('[Nn]') >> match('[Dd]')).as(:binary_op) >> spacing.maybe >> expression.as(:right) \
          | term.as(:left) >> spacing.maybe >> (match('[Oo]') >> match('[Rr]')).as(:binary_op) >> spacing.maybe >> expression.as(:right) \
          )
        }
        rule(:unary_expression) {
          ( spacing.maybe >> str('!').as(:unary_op) >> atom.as(:expression) \
          | spacing.maybe >> str('~').as(:unary_op) >> atom.as(:expression) \
          | spacing.maybe >> str('not').as(:unary_op) >> atom.as(:expression) \
          )
        }
        rule(:term) {
          ( unary_expression \
          | atom \
          )
        }
        rule(:atom) {
          ( spacing.maybe >> str('(') >> expression >> str(')') >> spacing.maybe \
          | spacing.maybe >> identifier_regexp.as(:identifier_regexp) >> separator >> attribute_regexp.as(:attribute_regexp) >> spacing.maybe \
          | spacing.maybe >> identifier_regexp.as(:identifier_regexp) >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> separator >> attribute_glob.as(:attribute_glob) >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> separator >> attribute.as(:attribute) >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier)>> separator >> attribute_glob.as(:attribute_glob) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier)>> separator >> attribute.as(:attribute) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier) >> spacing.maybe \
          )
        }
        rule(:identifier_regexp) {
          ( str('/') >> (str('/').absent? >> any).repeat(0) >> str('/') \
          )
        }
        rule(:identifier_glob) {
          ( identifier.repeat(0) >> (glob >> identifier.maybe).repeat(1) \
          )
        }
        rule(:identifier) {
          ( match('[A-Za-z]') >> match('[-./0-9A-Z_a-z]').repeat(0) \
          )
        }
        rule(:separator) {
          ( str(':') \
          | str('=') \
          )
        }
        rule(:attribute_regexp) {
          ( str('/') >> (str('/').absent? >> any).repeat(0) >> str('/') \
          )
        }
        rule(:attribute_glob) {
          ( attribute.repeat(0) >> (glob >> attribute.maybe).repeat(1) \
          )
        }
        rule(:attribute) {
          ( match('[-./0-9:A-Z_a-z]').repeat(1) \
          )
        }
        rule(:glob) {
          ( str('*') | str('?') | str('[') | str(']') )
        }
        rule(:spacing) {
          ( match('[\t\n\r ]').repeat(1) \
          )
        }
      end

      class ExpressionTransformer < Parslet::Transform
        rule(:binary_op => simple(:binary_op), :left => simple(:left), :right => simple(:right)) {
          BinaryExpressionNode.new(binary_op, left, right)
        }
        rule(:unary_op => simple(:unary_op), :expression => simple(:expression)) {
          UnaryExpressionNode.new(unary_op, expression)
        }
        rule(:identifier_regexp => simple(:identifier_regexp), :attribute_regexp => simple(:attribute_regexp)) {
          TagRegexpExpressionNode.new(identifier_regexp.to_s, attribute_regexp.to_s)
        }
        rule(:identifier_regexp => simple(:identifier_regexp)) {
          TagRegexpExpressionNode.new(identifier_regexp.to_s, nil)
        }
        rule(:identifier_glob => simple(:identifier_glob), :attribute_glob => simple(:attribute_glob)) {
          TagGlobExpressionNode.new(identifier_glob.to_s, attribute_glob.to_s)
        }
        rule(:identifier_glob => simple(:identifier_glob), :attribute => simple(:attribute)) {
          TagGlobExpressionNode.new(identifier_glob.to_s, attribute.to_s)
        }
        rule(:identifier_glob => simple(:identifier_glob)) {
          TagGlobExpressionNode.new(identifier_glob.to_s, nil)
        }
        rule(:identifier => simple(:identifier), :attribute_glob => simple(:attribute_glob)) {
          TagGlobExpressionNode.new(identifier.to_s, attribute_glob.to_s)
        }
        rule(:identifier => simple(:identifier), :attribute => simple(:attribute)) {
          TagExpressionNode.new(identifier.to_s, attribute.to_s)
        }
        rule(:identifier => simple(:identifier)) {
          TagExpressionNode.new(identifier.to_s, nil)
        }
      end

      class ExpressionNode
        def evaluate(environment)
          raise(NotImplementedError)
        end
      end

      class BinaryExpressionNode < ExpressionNode
        def initialize(op, left, right)
          @op = op
          @left = left
          @right = right
        end
        def evaluate(environment)
          case @op
          when "&&", "&", /\Aand\z/i
            left_values = @left.evaluate(environment)
            if left_values.empty?
              []
            else
              (left_values & @right.evaluate(environment)).uniq
            end
          when "||", "|", /\Aor\z/i
            left_values = @left.evaluate(environment)
            (left_values | @right.evaluate(environment)).uniq
          else
            raise(SyntaxError.new("unknown binary operator: #{@op}"))
          end
        end
      end

      class UnaryExpressionNode < ExpressionNode
        def initialize(op, expression)
          @op = op
          @expression = expression
        end
        def evaluate(environment)
          case @op
          when "!", "~", /\Anot\z/i
            values = @expression.evaluate(environment)
            if values.empty?
              environment.execute(<<-EOS).map { |row| row.first }
                SELECT DISTINCT host_id FROM hosts_tags;
              EOS
            else
              environment.execute(<<-EOS % values.map { "?" }.join(", "), values).map { |row| row.first }
                SELECT DISTINCT host_id FROM hosts_tags WHERE host_id NOT IN (%s);
              EOS
            end
          else
            raise(SyntaxError.new("unknown unary operator: #{@op}"))
          end
        end
      end

      class TagExpressionNode < ExpressionNode
        def initialize(identifier, attribute)
          @identifier = identifier
          @attribute = attribute
        end
        attr_reader :identifier
        attr_reader :attribute
        def attribute?
          !attribute.nil?
        end
        def evaluate(environment)
          if attribute?
            values = environment.execute(<<-EOS, identifier, attribute).map { |row| row.first }
              SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                INNER JOIN tags ON hosts_tags.tag_id = tags.id
                  WHERE LOWER(tags.name) = LOWER(?) AND LOWER(tags.value) = LOWER(?);
            EOS
          else
            values = environment.execute(<<-EOS, identifier, identifier, identifier).map { |row| row.first }
              SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                INNER JOIN tags ON hosts_tags.tag_id = tags.id
                  WHERE LOWER(hosts.name) = LOWER(?) OR LOWER(tags.name) = LOWER(?) OR LOWER(tags.value) = LOWER(?);
            EOS
          end
          if not environment.fixed_string? and values.empty?
            # fallback to glob expression
            identifier_glob = identifier.gsub(/[-.\/_]/, "?")
            if identifier != identifier_glob
              if attribute?
                attribute_glob = attribute.gsub(/[-.\/:_]/, "?")
                environment.logger.info("fallback to glob expression: %s:%s" % [identifier_glob, attribute_glob])
              else
                attribute_glob = nil
                environment.logger.info("fallback to glob expression: %s" % [identifier_glob])
              end
              values = TagGlobExpressionNode.new(identifier_glob, attribute_glob).evaluate(environment)
            end
          end
          values
        end
      end

      class TagGlobExpressionNode < TagExpressionNode
        def evaluate(environment)
          if attribute?
            values = environment.execute(<<-EOS, identifier, attribute).map { |row| row.first }
              SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                INNER JOIN tags ON hosts_tags.tag_id = tags.id
                  WHERE LOWER(tags.name) GLOB LOWER(?) AND LOWER(tags.value) GLOB LOWER(?);
            EOS
          else
            values = environment.execute(<<-EOS, identifier, identifier, identifier).map { |row| row.first }
              SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                INNER JOIN tags ON hosts_tags.tag_id = tags.id
                  WHERE LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?);

            EOS
          end
          if not environment.fixed_string? and values.empty?
            # fallback to glob expression
            identifier_glob = identifier.gsub(/[-.\/_]/, "?")
            if identifier != identifier_glob
              if attribute?
                attribute_glob = attribute.gsub(/[-.\/:_]/, "?")
                environment.logger.info("fallback to glob expression: %s:%s" % [identifier_glob, attribute_glob])
              else
                attribute_glob = nil
                environment.logger.info("fallback to glob expression: %s" % [identifier_glob])
              end
              values = TagGlobExpressionNode.new(identifier_glob, attribute_glob).evaluate(environment)
            end
          end
          values
        end
      end

      class TagRegexpExpressionNode < TagExpressionNode
        def initialize(identifier, attribute)
          identifier = identifier.sub(%r{\A/(.*)/\z}) { $1 } if identifier
          attribute = attribute.sub(%r{\A/(.*)/\z}) { $1 } if attribute
          super(identifier, attribute)
        end
        def evaluate(environment)
          if attribute?
            environment.execute(<<-EOS, identifier, attribute).map { |row| row.first }
              SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                INNER JOIN tags ON hosts_tags.tag_id = tags.id
                  WHERE LOWER(tags.name) REGEXP LOWER(?) AND LOWER(tags.value) REGEXP LOWER(?);
            EOS
          else
            environment.execute(<<-EOS, identifier, identifier, identifier).map { |row| row.first }
              SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                INNER JOIN tags ON hosts_tags.tag_id = tags.id
                  WHERE LOWER(hosts.name) REGEXP LOWER(?) OR LOWER(tags.name) REGEXP LOWER(?) OR LOWER(tags.value) REGEXP LOWER(?);
            EOS
          end
        end
      end
    end
  end
end

# vim:set ft=ruby :
