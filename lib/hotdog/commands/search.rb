#!/usr/bin/env ruby

require "json"
require "parslet"

module Hotdog
  module Commands
    class Search < BaseCommand
      def run(args=[])
        search_options = {
        }
        optparse.on("-n", "--limit LIMIT", "Limit result set to specified size at most", Integer) do |limit|
          search_options[:limit] = limit
        end
        args = optparse.parse(args)
        expression = args.join(" ").strip
        if expression.empty?
          exit(1)
        end

        begin
          node = parse(expression)
        rescue Parslet::ParseFailed => error
          STDERR.puts("syntax error: " + error.cause.ascii_tree)
          exit(1)
        end

        result = evaluate(node, self).sort
        if 0 < result.length
          _result, fields = get_hosts_with_search_tags(result, node)
          result = _result.take(search_options.fetch(:limit, _result.size))
          STDOUT.print(format(result, fields: fields))
          if _result.length == result.length
            logger.info("found %d host(s)." % result.length)
          else
            logger.info("found %d host(s), limited to %d in result." % [_result.length, result.length])
          end
        else
          STDERR.puts("no match found: #{args.join(" ")}")
          exit(1)
        end
      end

      def get_hosts_with_search_tags(result, node)
        drilldown = ->(n){
          case
          when n[:left] && n[:right] then drilldown.(n[:left]) + drilldown.(n[:right])
          when n[:expression] then drilldown.(n[:expression])
          when n[:identifier] then [n[:identifier]]
          else []
          end
        }
        if @options[:display_search_tags]
          identifiers = drilldown.call(node).map(&:to_s)
          if @options[:primary_tag]
            tags = [@options[:primary_tag]] + identifiers
          else
            tags = identifiers
          end
        else
          tags = nil
        end
        get_hosts(result, tags)
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
        rule(:binary_op) {
          ( str('&') >> str('&').maybe \
          | str('|') >> str('|').maybe \
          | match('[Aa]') >> match('[Nn]') >> match('[Dd]') \
          | match('[Oo]') >> match('[Rr]') \
          )
        }
        rule(:binary_expression) {
          ( term.as(:left) >> spacing.maybe >> binary_op.as(:binary_op) >> spacing.maybe >> expression.as(:right) \
          | term.as(:left) >> spacing.maybe.as(:binary_op) >> expression.as(:right) \
          )
        }
        rule(:unary_op) {
          ( str('!') \
          | str('~') \
          | match('[Nn]') >> match('[Oo]') >> match('[Tt]') \
          )
        }
        rule(:unary_expression) {
          ( spacing.maybe >> unary_op.as(:unary_op) >> expression.as(:expression) \
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
          | spacing.maybe >> identifier_regexp.as(:identifier_regexp) >> separator >> spacing.maybe \
          | spacing.maybe >> identifier_regexp.as(:identifier_regexp) >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> separator >> attribute_glob.as(:attribute_glob) >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> separator >> attribute.as(:attribute) >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> separator >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier) >> separator >> attribute_glob.as(:attribute_glob) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier) >> separator >> attribute.as(:attribute) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier) >> separator >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier) >> spacing.maybe \
          | spacing.maybe >> separator >> attribute_regexp.as(:attribute_regexp) >> spacing.maybe \
          | spacing.maybe >> separator >> attribute_glob.as(:attribute_glob) >> spacing.maybe \
          | spacing.maybe >> separator >> attribute.as(:attribute) >> spacing.maybe \
          | spacing.maybe >> attribute_regexp.as(:attribute_regexp) >> spacing.maybe \
          | spacing.maybe >> attribute_glob.as(:attribute_glob) >> spacing.maybe \
          | spacing.maybe >> attribute.as(:attribute) >> spacing.maybe \
          )
        }
        rule(:identifier_regexp) {
          ( str('/') >> (str('/').absent? >> any).repeat(0) >> str('/') \
          )
        }
        rule(:identifier_glob) {
          ( unary_op.absent? >> binary_op.absent? >> identifier.repeat(0) >> (glob >> identifier.maybe).repeat(1) \
          )
        }
        rule(:identifier) {
          ( unary_op.absent? >> binary_op.absent? >> match('[A-Za-z]') >> match('[-./0-9A-Z_a-z]').repeat(0) \
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
          ( unary_op.absent? >> binary_op.absent? >> attribute.repeat(0) >> (glob >> attribute.maybe).repeat(1) \
          )
        }
        rule(:attribute) {
          ( unary_op.absent? >> binary_op.absent? >> match('[-./0-9:A-Z_a-z]').repeat(1) \
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
        rule(:attribute_regexp => simple(:attribute_regexp)) {
          TagRegexpExpressionNode.new(nil, attribute_regexp.to_s)
        }
        rule(:attribute_glob => simple(:attribute_glob)) {
          TagGlobExpressionNode.new(nil, attribute_glob.to_s)
        }
        rule(:attribute => simple(:attribute)) {
          TagExpressionNode.new(nil, attribute.to_s)
        }
      end

      class ExpressionNode
        def evaluate(environment, options={})
          raise(NotImplementedError)
        end
      end

      class BinaryExpressionNode < ExpressionNode
        attr_reader :left, :right

        def initialize(op, left, right)
          @op = op
          @op ||= "or" # use OR expression by default
          @left = left
          @right = right
        end
        def evaluate(environment, options={})
          case @op
          when "&&", "&", /\Aand\z/i
            left_values = @left.evaluate(environment)
            if left_values.empty?
              []
            else
              right_values = @right.evaluate(environment)
              (left_values & right_values)
            end
          when "||", "|", /\Aor\z/i
            left_values = @left.evaluate(environment)
            right_values = @right.evaluate(environment)
            (left_values | right_values).uniq
          else
            raise(SyntaxError.new("unknown binary operator: #{@op.inspect}"))
          end
        end
      end

      class UnaryExpressionNode < ExpressionNode
        attr_reader :expression

        def initialize(op, expression)
          @op = op
          @expression = expression
        end
        def evaluate(environment, options={})
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
            raise(SyntaxError.new("unknown unary operator: #{@op.inspect}"))
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
        def identifier?
          !(identifier.nil? or identifier.to_s.empty?)
        end
        def attribute?
          !(attribute.nil? or attribute.to_s.empty?)
        end
        def evaluate(environment, options={})
          if identifier?
            if attribute?
              case identifier
              when /\Ahost\z/i
                values = environment.execute(<<-EOS, [attribute]).map { |row| row.first }
                  SELECT hosts.id FROM hosts
                    WHERE hosts.name = ?;
                EOS
              else
                values = environment.execute(<<-EOS, [identifier, attribute]).map { |row| row.first }
                  SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                    INNER JOIN tags ON hosts_tags.tag_id = tags.id
                      WHERE tags.name = ? AND tags.value = ?;
                EOS
              end
            else
              values = environment.execute(<<-EOS, [identifier, identifier, identifier]).map { |row| row.first }
                SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                  INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE hosts.name = ? OR tags.name = ? OR tags.value = ?;
              EOS
            end
          else
            if attribute?
              values = environment.execute(<<-EOS, [attribute]).map { |row| row.first }
                SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE tags.value = ?;
              EOS
            else
              return []
            end
          end
          if values.empty?
            fallback(environment, options)
          else
            values
          end
        end

        def fallback(environment, options={})
          if environment.fixed_string?
            []
          else
            # fallback to glob expression
            identifier_glob = identifier.gsub(/[-.\/_]/, "?") if identifier?
            attribute_glob = attribute.gsub(/[-.\/_]/, "?") if attribute?
            if (identifier? and identifier != identifier_glob) or (attribute? and attribute != attribute_glob)
              environment.logger.info("fallback to glob expression: %s:%s" % [identifier_glob, attribute_glob])
              values = TagGlobExpressionNode.new(identifier_glob, attribute_glob).evaluate(environment, options)
              if values.empty?
                reload(environment, options)
              else
                values
              end
            else
              []
            end
          end
        end

        def reload(environment, options={})
          ttl = options.fetch(:ttl, 1)
          if 0 < ttl
            environment.logger.info("force reloading all hosts and tags.")
            environment.reload(force: true)
            self.class.new(identifier, attribute).evaluate(environment, options.merge(ttl: ttl-1))
          else
            []
          end
        end
      end

      class TagGlobExpressionNode < TagExpressionNode
        def evaluate(environment, options={})
          if identifier?
            if attribute?
              case identifier
              when /\Ahost\z/i
                values = environment.execute(<<-EOS, [attribute]).map { |row| row.first }
                  SELECT hosts.id FROM hosts
                    WHERE hosts.name GLOB ?;
                EOS
              else
                values = environment.execute(<<-EOS, [identifier, attribute]).map { |row| row.first }
                  SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                    INNER JOIN tags ON hosts_tags.tag_id = tags.id
                      WHERE tags.name GLOB ? AND tags.value GLOB ?;
                EOS
              end
            else
              values = environment.execute(<<-EOS, [identifier, identifier, identifier]).map { |row| row.first }
                SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                  INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE hosts.name GLOB ? OR tags.name GLOB ? OR tags.value GLOB ?;
              EOS
            end
          else
            if attribute?
              values = environment.execute(<<-EOS, [attribute]).map { |row| row.first }
                SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE tags.value GLOB ?;
              EOS
            else
              return []
            end
          end
          if values.empty?
            fallback(environment, options)
          else
            values
          end
        end
      end

      class TagRegexpExpressionNode < TagExpressionNode
        def initialize(identifier, attribute)
          identifier = identifier.sub(%r{\A/(.*)/\z}) { $1 } if identifier
          attribute = attribute.sub(%r{\A/(.*)/\z}) { $1 } if attribute
          super(identifier, attribute)
        end
        def evaluate(environment, options={})
          if identifier?
            if attribute?
              case identifier
              when /\Ahost\z/i
                values = environment.execute(<<-EOS, [attribute]).map { |row| row.first }
                  SELECT hosts.id FROM hosts
                    WHERE hosts.name REGEXP ?;
                EOS
              else
                values = environment.execute(<<-EOS, [identifier, attribute]).map { |row| row.first }
                  SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                    INNER JOIN tags ON hosts_tags.tag_id = tags.id
                      WHERE tags.name REGEXP ? AND tags.value REGEXP ?;
                EOS
              end
            else
              values = environment.execute(<<-EOS, [identifier, identifier, identifier]).map { |row| row.first }
                SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                  INNER JOIN hosts ON hosts_tags.host_id = hosts.id
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE hosts.name REGEXP ? OR tags.name REGEXP ? OR tags.value REGEXP ?;
              EOS
            end
          else
            if attribute?
              values = environment.execute(<<-EOS, [attribute]).map { |row| row.first }
                SELECT DISTINCT hosts_tags.host_id FROM hosts_tags
                  INNER JOIN tags ON hosts_tags.tag_id = tags.id
                    WHERE tags.value REGEXP ?;
              EOS
            else
              return []
            end
          end
          if values.empty?
            reload(environment)
          else
            values
          end
        end
      end
    end
  end
end

# vim:set ft=ruby :
