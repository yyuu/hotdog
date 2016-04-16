#!/usr/bin/env ruby

require "json"
require "parslet"

# Monkey patch to prevent `NoMethodError` after some parse error in parselet
module Parslet
  class Cause
    def cause
      self
    end

    def backtrace
      []
    end
  end
end

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
          @remote_command = args.slice(args.index("--") + 1, args.length).join(" ")
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
          when n[:identifier] then [n[:identifier]]
          else []
          end
        }
        if options[:display_search_tags]
          identifiers = drilldown.call(node).map(&:to_s)
          if options[:primary_tag]
            tags = [options[:primary_tag]] + identifiers
          else
            tags = identifiers
          end
        else
          tags = nil
        end
        get_hosts(result, tags)
      end

      def parse(expression)
        logger.debug(expression)
        parser = ExpressionParser.new
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
        node = ExpressionTransformer.new.apply(data)
        optimized = node.optimize.tap do |optimized|
          logger.debug {
            JSON.pretty_generate(optimized.dump)
          }
        end
        optimized.evaluate(environment)
      end

      class ExpressionParser < Parslet::Parser
        root(:expression)
        rule(:expression) {
          ( expression0 \
          )
        }
        rule(:expression0) {
          ( expression1.as(:left) >> spacing.maybe >> binary_op.as(:binary_op) >> spacing.maybe >> expression.as(:right) \
          | expression1 \
          )
        }
        rule(:expression1) {
          ( unary_op.as(:unary_op) >> spacing >> expression.as(:expression) \
          | unary_op.as(:unary_op) >> spacing.maybe >> str('(') >> spacing.maybe >> expression.as(:expression) >> spacing.maybe >> str(')') \
          | expression2 \
          )
        }
        rule(:expression2) {
          ( expression3.as(:left) >> spacing.maybe.as(:binary_op) >> expression.as(:right) \
          | expression3 \
          )
        }
        rule(:expression3) {
          ( expression4.as(:left) >> spacing.maybe >> str('&&').as(:binary_op) >> spacing.maybe >> expression.as(:right) \
          | expression4.as(:left) >> spacing.maybe >> str('||').as(:binary_op) >> spacing.maybe >> expression.as(:right) \
          | expression4.as(:left) >> spacing.maybe >> str('&').as(:binary_op) >> spacing.maybe >> expression.as(:right) \
          | expression4.as(:left) >> spacing.maybe >> str(',').as(:binary_op) >> spacing.maybe >> expression.as(:right) \
          | expression4.as(:left) >> spacing.maybe >> str('^').as(:binary_op) >> spacing.maybe >> expression.as(:right) \
          | expression4.as(:left) >> spacing.maybe >> str('|').as(:binary_op) >> spacing.maybe >> expression.as(:right) \
          | expression4 \
          )
        }
        rule(:expression4) {
          ( str('!').as(:unary_op) >> spacing.maybe >> atom.as(:expression) \
          | str('~').as(:unary_op) >> spacing.maybe >> atom.as(:expression) \
          | str('!').as(:unary_op) >> spacing.maybe >> expression.as(:expression) \
          | str('~').as(:unary_op) >> spacing.maybe >> expression.as(:expression) \
          | atom \
          )
        }
        rule(:binary_op) {
          ( str('AND') \
          | str('OR') \
          | str('XOR') \
          | str('and') \
          | str('or') \
          | str('xor') \
          )
        }
        rule(:unary_op) {
          ( str('NOT') \
          | str('not') \
          )
        }
        rule(:atom) {
          ( spacing.maybe >> str('(') >> expression >> str(')') >> spacing.maybe \
          | spacing.maybe >> str('/') >> identifier_regexp.as(:identifier_regexp) >> str('/') >> separator.as(:separator) >> str('/') >> attribute_regexp.as(:attribute_regexp) >> str('/') >> spacing.maybe \
          | spacing.maybe >> str('/') >> identifier_regexp.as(:identifier_regexp) >> str('/') >> separator.as(:separator) >> spacing.maybe \
          | spacing.maybe >> str('/') >> identifier_regexp.as(:identifier_regexp) >> str('/') >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> separator.as(:separator) >> attribute_glob.as(:attribute_glob) >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> separator.as(:separator) >> attribute.as(:attribute) >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> separator.as(:separator) >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier) >> separator.as(:separator) >> attribute_glob.as(:attribute_glob) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier) >> separator.as(:separator) >> attribute.as(:attribute) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier) >> separator.as(:separator) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier) >> spacing.maybe \
          | spacing.maybe >> separator.as(:separator) >> str('/') >> attribute_regexp.as(:attribute_regexp) >> str('/') >> spacing.maybe \
          | spacing.maybe >> separator.as(:separator) >> attribute_glob.as(:attribute_glob) >> spacing.maybe \
          | spacing.maybe >> separator.as(:separator) >> attribute.as(:attribute) >> spacing.maybe \
          | spacing.maybe >> str('/') >> attribute_regexp.as(:attribute_regexp) >> str('/') >> spacing.maybe \
          | spacing.maybe >> attribute_glob.as(:attribute_glob) >> spacing.maybe \
          | spacing.maybe >> attribute.as(:attribute) >> spacing.maybe \
          )
        }
        rule(:identifier_regexp) {
          ( (str('/').absent? >> any).repeat(0) \
          )
        }
        rule(:identifier_glob) {
          ( binary_op.absent? >> unary_op.absent? >> identifier.repeat(0) >> (glob >> identifier.maybe).repeat(1) \
          | binary_op >> (glob >> identifier.maybe).repeat(1) \
          | unary_op >> (glob >> identifier.maybe).repeat(1) \
          )
        }
        rule(:identifier) {
          ( binary_op.absent? >> unary_op.absent? >> match('[A-Za-z]') >> match('[-./0-9A-Z_a-z]').repeat(0) \
          | binary_op >> match('[-./0-9A-Z_a-z]').repeat(1) \
          | unary_op >> match('[-./0-9A-Z_a-z]').repeat(1) \
          )
        }
        rule(:separator) {
          ( str(':') \
          | str('=') \
          )
        }
        rule(:attribute_regexp) {
          ( (str('/').absent? >> any).repeat(0) \
          )
        }
        rule(:attribute_glob) {
          ( binary_op.absent? >> unary_op.absent? >> attribute.repeat(0) >> (glob >> attribute.maybe).repeat(1) \
          | binary_op >> (glob >> attribute.maybe).repeat(1) \
          | unary_op >> (glob >> attribute.maybe).repeat(1) \
          )
        }
        rule(:attribute) {
          ( binary_op.absent? >> unary_op.absent? >> match('[-./0-9:A-Z_a-z]').repeat(1) \
          | binary_op >> match('[-./0-9:A-Z_a-z]').repeat(1) \
          | unary_op >> match('[-./0-9:A-Z_a-z]').repeat(1) \
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
        rule(binary_op: simple(:binary_op), left: simple(:left), right: simple(:right)) {
          BinaryExpressionNode.new(binary_op, left, right)
        }
        rule(unary_op: simple(:unary_op), expression: simple(:expression)) {
          UnaryExpressionNode.new(unary_op, expression)
        }
        rule(identifier_regexp: simple(:identifier_regexp), separator: simple(:separator), attribute_regexp: simple(:attribute_regexp)) {
          if "host" == identifier_regexp
            RegexpHostNode.new(attribute_regexp.to_s, separator)
          else
            RegexpTagNode.new(identifier_regexp.to_s, attribute_regexp.to_s, separator)
          end
        }
        rule(identifier_regexp: simple(:identifier_regexp), separator: simple(:separator)) {
          if "host" == identifier_regexp
            EverythingNode.new()
          else
            RegexpTagNameNode.new(identifier_regexp.to_s, separator)
          end
        }
        rule(identifier_regexp: simple(:identifier_regexp)) {
          if "host" == identifier_regexp
            EverythingNode.new()
          else
            RegexpNode.new(identifier_regexp.to_s)
          end
        }
        rule(identifier_glob: simple(:identifier_glob), separator: simple(:separator), attribute_glob: simple(:attribute_glob)) {
          if "host" == identifier_glob
            GlobHostNode.new(attribute_glob.to_s, separator)
          else
            GlobTagNode.new(identifier_glob.to_s, attribute_glob.to_s, separator)
          end
        }
        rule(identifier_glob: simple(:identifier_glob), separator: simple(:separator), attribute: simple(:attribute)) {
          if "host" == identifier_glob
            GlobHostNode.new(attribute.to_s, separator)
          else
            GlobTagNode.new(identifier.to_s, attribute.to_s, separator)
          end
        }
        rule(identifier_glob: simple(:identifier_glob), separator: simple(:separator)) {
          if "host" == identifier_glob
            EverythingNode.new()
          else
            GlobTagNameNode.new(identifier_glob.to_s, separator)
          end
        }
        rule(identifier_glob: simple(:identifier_glob)) {
          if "host" == identifier_glob
            EverythingNode.new()
          else
            GlobNode.new(identifier_glob.to_s)
          end
        }
        rule(identifier: simple(:identifier), separator: simple(:separator), attribute_glob: simple(:attribute_glob)) {
          if "host" == identifier
            GlobHostNode.new(attribute_glob.to_s, separator)
          else
            GlobTagNode.new(identifier.to_s, attribute_glob.to_s, separator)
          end
        }
        rule(identifier: simple(:identifier), separator: simple(:separator), attribute: simple(:attribute)) {
          if "host" == identifier
            StringHostNode.new(attribute.to_s, separator)
          else
            StringTagNode.new(identifier.to_s, attribute.to_s, separator)
          end
        }
        rule(identifier: simple(:identifier), separator: simple(:separator)) {
          if "host" == identifier
            EverythingNode.new()
          else
            StringTagNameNode.new(identifier.to_s, separator)
          end
        }
        rule(identifier: simple(:identifier)) {
          if "host" == identifier
            EverythingNode.new()
          else
            StringNode.new(identifier.to_s)
          end
        }
        rule(separator: simple(:separator), attribute_regexp: simple(:attribute_regexp)) {
          RegexpTagValueNode.new(attribute_regexp.to_s, separator)
        }
        rule(attribute_regexp: simple(:attribute_regexp)) {
          RegexpTagValueNode.new(attribute_regexp.to_s)
        }
        rule(separator: simple(:separator), attribute_glob: simple(:attribute_glob)) {
          GlobTagValueNode.new(attribute_glob.to_s, separator)
        }
        rule(attribute_glob: simple(:attribute_glob)) {
          GlobTagValueNode.new(attribute_glob.to_s)
        }
        rule(separator: simple(:separator), attribute: simple(:attribute)) {
          StringTagValueNode.new(attribute.to_s, separator)
        }
        rule(attribute: simple(:attribute)) {
          StringTagValueNode.new(attribute.to_s)
        }
      end

      class ExpressionNode
        def evaluate(environment, options={})
          raise(NotImplementedError.new("must be overridden"))
        end

        def optimize(options={})
          self
        end

        def dump(options={})
          {}
        end

        def intermediates()
          []
        end

        def leafs()
          [self]
        end
      end

      class UnaryExpressionNode < ExpressionNode
        attr_reader :op, :expression

        def initialize(op, expression)
          case (op || "not").to_s
          when "!", "~", /\Anot\z/i
            @op = :NOT
          else
            raise(SyntaxError.new("unknown unary operator: #{@op.inspect}"))
          end
          @expression = expression
        end

        def evaluate(environment, options={})
          case @op
          when :NOT
            values = @expression.evaluate(environment, options).tap do |values|
              environment.logger.debug("expr: #{values.length} value(s)")
            end
            if values.empty?
              EverythingNode.new().evaluate(environment, options).tap do |values|
                environment.logger.debug("NOT expr: #{values.length} value(s)")
              end
            else
              # workaround for "too many terms in compound SELECT"
              min, max = environment.execute("SELECT MIN(id), MAX(id) FROM hosts ORDER BY id LIMIT 1").first.to_a
              (min / (SQLITE_LIMIT_COMPOUND_SELECT - 2)).upto(max / (SQLITE_LIMIT_COMPOUND_SELECT - 2)).flat_map { |i|
                range = ((SQLITE_LIMIT_COMPOUND_SELECT - 2) * i)...((SQLITE_LIMIT_COMPOUND_SELECT - 2) * (i + 1))
                selected = values.select { |n| range === n }
                q = "SELECT id FROM hosts " \
                      "WHERE ? <= id AND id < ? AND id NOT IN (%s);"
                environment.execute(q % selected.map { "?" }.join(", "), [range.first, range.last] + selected).map { |row| row.first }
              }.tap do |values|
                environment.logger.debug("NOT expr: #{values.length} value(s)")
              end
            end
          else
            []
          end
        end

        def optimize(options={})
          @expression = @expression.optimize(options)
          case op
          when :NOT
            case expression
            when EverythingNode
              NothingNode.new(options)
            when NothingNode
              EverythingNode.new(options)
            else
              optimize1(options)
            end
          else
            self
          end
        end

        def ==(other)
          self.class === other and @op == other.op and @expression == other.expression
        end

        def dump(options={})
          {unary_op: @op.to_s, expression: @expression.dump(options)}
        end

        def intermediates()
          [self] + @expression.intermediates
        end

        def leafs()
          @expression.leafs
        end

        private
        def optimize1(options={})
          case op
          when :NOT
            if UnaryExpressionNode === expression and expression.op == :NOT
              expression.expression
            else
              case expression
              when QueryExpressionNode
                q = expression.query
                v = expression.values
                if q and v.length <= SQLITE_LIMIT_COMPOUND_SELECT
                  QueryExpressionNode.new("SELECT id AS host_id FROM hosts EXCEPT #{q.sub(/\s*;\s*\z/, "")};", v)
                else
                  self
                end
              when TagExpressionNode
                q = expression.maybe_query(options)
                v = expression.condition_values(options)
                if q and v.length <= SQLITE_LIMIT_COMPOUND_SELECT
                  QueryExpressionNode.new("SELECT id AS host_id FROM hosts EXCEPT #{q.sub(/\s*;\s*\z/, "")};", v)
                else
                  self
                end
              else
                self
              end
            end
          else
            self
          end
        end
      end

      class BinaryExpressionNode < ExpressionNode
        attr_reader :op, :left, :right

        def initialize(op, left, right)
          case (op || "or").to_s
          when "&&", "&", "AND", "and"
            @op = :AND
          when ",", "||", "|", "OR", "or"
            @op = :OR
          when "^", "XOR", "xor"
            @op = :XOR
          else
            raise(SyntaxError.new("unknown binary operator: #{op.inspect}"))
          end
          @left = left
          @right = right
        end

        def evaluate(environment, options={})
          case @op
          when :AND
            left_values = @left.evaluate(environment, options).tap do |values|
              environment.logger.debug("lhs: #{values.length} value(s)")
            end
            if left_values.empty?
              []
            else
              right_values = @right.evaluate(environment, options).tap do |values|
                environment.logger.debug("rhs: #{values.length} value(s)")
              end
              if right_values.empty?
                []
              else
                # workaround for "too many terms in compound SELECT"
                min, max = environment.execute("SELECT MIN(id), MAX(id) FROM hosts ORDER BY id LIMIT 1").first.to_a
                (min / ((SQLITE_LIMIT_COMPOUND_SELECT - 2) / 2)).upto(max / ((SQLITE_LIMIT_COMPOUND_SELECT - 2) / 2)).flat_map { |i|
                  range = (((SQLITE_LIMIT_COMPOUND_SELECT - 2) / 2) * i)...(((SQLITE_LIMIT_COMPOUND_SELECT - 2) / 2) * (i + 1))
                  left_selected = left_values.select { |n| range === n }
                  right_selected = right_values.select { |n| range === n }
                  q = "SELECT id FROM hosts " \
                        "WHERE ? <= id AND id < ? AND ( id IN (%s) AND id IN (%s) );"
                  environment.execute(q % [left_selected.map { "?" }.join(", "), right_selected.map { "?" }.join(", ")], [range.first, range.last] + left_selected + right_selected).map { |row| row.first }
                }.tap do |values|
                  environment.logger.debug("lhs AND rhs: #{values.length} value(s)")
                end
              end
            end
          when :OR
            left_values = @left.evaluate(environment, options).tap do |values|
              environment.logger.debug("lhs: #{values.length} value(s)")
            end
            right_values = @right.evaluate(environment, options).tap do |values|
              environment.logger.debug("rhs: #{values.length} value(s)")
            end
            if left_values.empty?
              right_values
            else
              if right_values.empty?
                []
              else
                # workaround for "too many terms in compound SELECT"
                min, max = environment.execute("SELECT MIN(id), MAX(id) FROM hosts ORDER BY id LIMIT 1").first.to_a
                (min / ((SQLITE_LIMIT_COMPOUND_SELECT - 2) / 2)).upto(max / ((SQLITE_LIMIT_COMPOUND_SELECT - 2) / 2)).flat_map { |i|
                  range = (((SQLITE_LIMIT_COMPOUND_SELECT - 2) / 2) * i)...(((SQLITE_LIMIT_COMPOUND_SELECT - 2) / 2) * (i + 1))
                  left_selected = left_values.select { |n| range === n }
                  right_selected = right_values.select { |n| range === n }
                  q = "SELECT id FROM hosts " \
                        "WHERE ? <= id AND id < ? AND ( id IN (%s) OR id IN (%s) );"
                  environment.execute(q % [left_selected.map { "?" }.join(", "), right_selected.map { "?" }.join(", ")], [range.first, range.last] + left_selected + right_selected).map { |row| row.first }
                }.tap do |values|
                  environment.logger.debug("lhs OR rhs: #{values.length} value(s)")
                end
              end
            end
          when :XOR
            left_values = @left.evaluate(environment, options).tap do |values|
              environment.logger.debug("lhs: #{values.length} value(s)")
            end
            right_values = @right.evaluate(environment, options).tap do |values|
              environment.logger.debug("rhs: #{values.length} value(s)")
            end
            if left_values.empty?
              right_values
            else
              if right_values.empty?
                []
              else
                # workaround for "too many terms in compound SELECT"
                min, max = environment.execute("SELECT MIN(id), MAX(id) FROM hosts ORDER BY id LIMIT 1").first.to_a
                (min / ((SQLITE_LIMIT_COMPOUND_SELECT - 2) / 4)).upto(max / ((SQLITE_LIMIT_COMPOUND_SELECT - 2) / 4)).flat_map { |i|
                  range = (((SQLITE_LIMIT_COMPOUND_SELECT - 2) / 4) * i)...(((SQLITE_LIMIT_COMPOUND_SELECT - 2) / 4) * (i + 1))
                  left_selected = left_values.select { |n| range === n }
                  right_selected = right_values.select { |n| range === n }
                  q = "SELECT id FROM hosts " \
                        "WHERE ? <= id AND id < ? AND NOT (id IN (%s) AND id IN (%s)) AND ( id IN (%s) OR id IN (%s) );"
                  lq = left_selected.map { "?" }.join(", ")
                  rq = right_selected.map { "?" }.join(", ")
                  environment.execute(q % [lq, rq, lq, rq], [range.first, range.last] + left_selected + right_selected + left_selected + right_selected).map { |row| row.first }
                }.tap do |values|
                  environment.logger.debug("lhs XOR rhs: #{values.length} value(s)")
                end
              end
            end
          else
            []
          end
        end

        def optimize(options={})
          @left = @left.optimize(options)
          @right = @right.optimize(options)
          case op
          when :AND
            case left
            when EverythingNode
              right
            when NothingNode
              left
            else
              if left == right
                left
              else
                optimize1(options)
              end
            end
          when :OR
            case left
            when EverythingNode
              left
            when NothingNode
              left
            else
              if left == right
                left
              else
                if MultinaryExpressionNode === left
                  if left.op == op
                    left.merge(right, fallback: self)
                  else
                    optimize1(options)
                  end
                else
                  if MultinaryExpressionNode === right
                    if right.op == op
                      right.merge(left, fallback: self)
                    else
                      optimize1(options)
                    end
                  else
                    MultinaryExpressionNode.new(op, [left, right], fallback: self)
                  end
                end
              end
            end
          when :XOR
            if left == right
              []
            else
              optimize1(options)
            end
          else
            self
          end
        end

        def ==(other)
          self.class === other and @op == other.op and @left == other.left and @right == other.right
        end

        def dump(options={})
          {left: @left.dump(options), binary_op: @op.to_s, right: @right.dump(options)}
        end

        def intermediates()
          [self] + @left.intermediates + @right.intermediates
        end

        def leafs()
          @left.leafs + @right.leafs
        end

        private
        def optimize1(options)
          if TagExpressionNode === left and TagExpressionNode === right
            lq = left.maybe_query(options)
            lv = left.condition_values(options)
            rq = right.maybe_query(options)
            rv = right.condition_values(options)
            if lq and rq and lv.length + rv.length <= SQLITE_LIMIT_COMPOUND_SELECT
              case op
              when :AND
                q = "#{lq.sub(/\s*;\s*\z/, "")} INTERSECT #{rq.sub(/\s*;\s*\z/, "")};"
                QueryExpressionNode.new(q, lv + rv, fallback: self)
              when :OR
                q = "#{lq.sub(/\s*;\s*\z/, "")} UNION #{rq.sub(/\s*;\s*\z/, "")};"
                QueryExpressionNode.new(q, lv + rv, fallback: self)
              when :XOR
                q = "#{lq.sub(/\s*;\s*\z/, "")} UNION #{rq.sub(/\s*;\s*\z/, "")} " \
                      "EXCEPT #{lq.sub(/\s*;\s*\z/, "")} " \
                        "INTERSECT #{rq.sub(/\s*;\s*\z/, "")};"
                QueryExpressionNode.new(q, lv + rv, fallback: self)
              else
                self
              end
            else
              self
            end
          else
            self
          end
        end
      end

      class MultinaryExpressionNode < ExpressionNode
        attr_reader :op, :expressions

        def initialize(op, expressions, options={})
          case (op || "or").to_s
          when ",", "||", "|", "OR", "or"
            @op = :OR
          else
            raise(SyntaxError.new("unknown multinary operator: #{op.inspect}"))
          end
          if SQLITE_LIMIT_COMPOUND_SELECT < expressions.length
            raise(ArgumentError.new("expressions limit exceeded: #{expressions.length} for #{SQLITE_LIMIT_COMPOUND_SELECT}"))
          end
          @expressions = expressions
          @fallback = options[:fallback]
        end

        def merge(other, options={})
          if MultinaryExpressionNode === other and op == other.op
            MultinaryExpressionNode.new(op, expressions + other.expressions, options)
          else
            MultinaryExpressionNode.new(op, expressions + [other], options)
          end
        end

        def evaluate(environment, options={})
          case @op
          when :OR
            if expressions.all? { |expression| TagExpressionNode === expression }
              values = expressions.group_by { |expression| expression.class }.values.flat_map { |expressions|
                query_without_condition = expressions.first.maybe_query_without_condition(options)
                if query_without_condition
                  condition_length = expressions.map { |expression| expression.condition_values(options).length }.max
                  expressions.each_slice(SQLITE_LIMIT_COMPOUND_SELECT / condition_length).flat_map { |expressions|
                    q = query_without_condition.sub(/\s*;\s*\z/, "") + " WHERE " + expressions.map { |expression| "( %s )" % expression.condition(options) }.join(" OR ") + ";"
                    environment.execute(q, expressions.flat_map { |expression| expression.condition_values(options) }).map { |row| row.first }
                  }
                else
                  []
                end
              }
            else
              values = []
            end
          else
            values = []
          end
          if values.empty?
            if @fallback
              @fallback.evaluate(environment, options={})
            else
              []
            end
          else
            values
          end
        end

        def dump(options={})
          {multinary_op: @op.to_s, expressions: expressions.map { |expression| expression.dump(options) }}
        end

        def intermediates()
          [self] + @expression.flat_map { |expression| expression.intermediates }
        end

        def leafs()
          @expressions.flat_map { |expression| expression.leafs }
        end
      end

      class QueryExpressionNode < ExpressionNode
        def initialize(query, values=[], options={})
          @query = query
          @values = values
          @fallback = options[:fallback]
        end
        attr_reader :query
        attr_reader :values

        def evaluate(environment, options={})
          values = environment.execute(@query, @values).map { |row| row.first }
          if values.empty? and @fallback
            @fallback.evaluate(environment, options)
          else
            values
          end
        end

        def dump(options={})
          data = {query: @query, values: @values}
          data[:fallback] = @fallback.dump(options) if @fallback
          data
        end
      end

      class EverythingNode < QueryExpressionNode
        def initialize(options={})
          super("SELECT id AS host_id FROM hosts", [], options)
        end
      end

      class NothingNode < QueryExpressionNode
        def initialize(options={})
          super("SELECT NULL AS host_id WHERE host_id NOT NULL", [], options)
        end

        def evaluate(environment, options={})
          if @fallback
            @fallback.evaluate(environment, options)
          else
            []
          end
        end
      end

      class TagExpressionNode < ExpressionNode
        def initialize(identifier, attribute, separator=nil)
          @identifier = identifier
          @attribute = attribute
          @separator = separator
          @fallback = nil
        end
        attr_reader :identifier
        attr_reader :attribute
        attr_reader :separator

        def identifier?
          !(identifier.nil? or identifier.to_s.empty?)
        end

        def attribute?
          !(attribute.nil? or attribute.to_s.empty?)
        end

        def separator?
          !(separator.nil? or separator.to_s.empty?)
        end

        def maybe_query(options={})
          query_without_condition = maybe_query_without_condition(options)
          if query_without_condition
            query_without_condition.sub(/\s*;\s*\z/, "") + " WHERE " + condition(options) + ";"
          else
            nil
          end
        end

        def maybe_query_without_condition(options={})
          tables = condition_tables(options)
          if tables.empty?
            nil
          else
            case tables
            when [:hosts]
              "SELECT hosts.id AS host_id FROM hosts;"
            when [:hosts, :tags]
              "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags INNER JOIN hosts ON hosts_tags.host_id = hosts.id INNER JOIN tags ON hosts_tags.tag_id = tags.id;"
            when [:tags]
              "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags INNER JOIN tags ON hosts_tags.tag_id = tags.id;"
            else
              raise(NotImplementedError.new("unknown tables: #{tables.join(", ")}"))
            end
          end
        end

        def condition(options={})
          raise(NotImplementedError.new("must be overridden"))
        end

        def condition_tables(options={})
          raise(NotImplementedError.new("must be overridden"))
        end

        def condition_values(options={})
          raise(NotImplementedError.new("must be overridden"))
        end

        def evaluate(environment, options={})
          q = maybe_query(options)
          if q
            values = environment.execute(q, condition_values(options)).map { |row| row.first }
            if values.empty?
              if options[:did_fallback]
                []
              else
                if not environment.fixed_string? and @fallback
                  # avoid optimizing @fallback to prevent infinite recursion
                  values = @fallback.evaluate(environment, options.merge(did_fallback: true))
                  if values.empty?
                    if reload(environment, options)
                      evaluate(environment, options).tap do |values|
                        if values.empty?
                          environment.logger.info("no result: #{self.dump.inspect}")
                        end
                      end
                    else
                      []
                    end
                  else
                    values
                  end
                else
                  if reload(environment, options)
                    evaluate(environment, options).tap do |values|
                      if values.empty?
                        environment.logger.info("no result: #{self.dump.inspect}")
                      end
                    end
                  else
                    []
                  end
                end
              end
            else
              values
            end
          else
            []
          end
        end

        def ==(other)
          self.class == other.class and @identifier == other.identifier and @attribute == other.attribute
        end

        def optimize(options={})
          # fallback to glob expression
          @fallback = maybe_fallback(options)
          self
        end

        def to_glob(s)
          (s.start_with?("*") ? "" : "*") + s.gsub(/[-.\/_]/, "?") + (s.end_with?("*") ? "" : "*")
        end

        def maybe_glob(s)
          s ? to_glob(s.to_s) : nil
        end

        def reload(environment, options={})
          $did_reload ||= false
          if $did_reload
            false
          else
            $did_reload = true
            environment.logger.info("force reloading all hosts and tags.")
            environment.reload(force: true)
            true
          end
        end

        def dump(options={})
          data = {}
          data[:identifier] = identifier.to_s if identifier
          data[:separator] = separator.to_s if separator
          data[:attribute] = attribute.to_s if attribute
          data[:fallback ] = @fallback.dump(options) if @fallback
          data
        end

        def maybe_fallback(options={})
          nil
        end
      end

      class AnyHostNode < TagExpressionNode
        def initialize(separator=nil)
          super("host", nil, separator)
        end

        def condition(options={})
          "1"
        end

        def condition_tables(options={})
          [:hosts]
        end

        def condition_values(options={})
          []
        end
      end

      class StringExpressionNode < TagExpressionNode
      end

      class StringHostNode < StringExpressionNode
        def initialize(attribute, separator=nil)
          super("host", attribute, separator)
        end

        def condition(options={})
          "hosts.name = ?"
        end

        def condition_tables(options={})
          [:hosts]
        end

        def condition_values(options={})
          [attribute]
        end

        def maybe_fallback(options={})
          fallback = GlobHostNode.new(to_glob(attribute), separator)
          query = fallback.maybe_query(options)
          if query
            QueryExpressionNode.new(query, fallback.condition_values(options))
          else
            nil
          end
        end
      end

      class StringTagNode < StringExpressionNode
        def initialize(identifier, attribute, separator=nil)
          super(identifier, attribute, separator)
        end

        def condition(options={})
          "tags.name = ? AND tags.value = ?"
        end

        def condition_tables(options={})
          [:tags]
        end

        def condition_values(options={})
          [identifier, attribute]
        end

        def maybe_fallback(options={})
          fallback = GlobTagNode.new(to_glob(identifier), to_glob(attribute), separator)
          query = fallback.maybe_query(options)
          if query
            QueryExpressionNode.new(query, fallback.condition_values(options))
          else
            nil
          end
        end
      end

      class StringTagNameNode < StringExpressionNode
        def initialize(identifier, separator=nil)
          super(identifier, nil, separator)
        end

        def condition(options={})
          "tags.name = ?"
        end

        def condition_tables(options={})
          [:tags]
        end

        def condition_values(options={})
          [identifier]
        end

        def maybe_fallback(options={})
          fallback = GlobTagNameNode.new(to_glob(identifier), separator)
          query = fallback.maybe_query(options)
          if query
            QueryExpressionNode.new(query, fallback.condition_values(options))
          else
            nil
          end
        end
      end

      class StringTagValueNode < StringExpressionNode
        def initialize(attribute, separator=nil)
          super(nil, attribute, separator)
        end

        def condition(options={})
          "hosts.name = ? OR tags.value = ?"
        end

        def condition_tables(options={})
          [:hosts, :tags]
        end

        def condition_values(options={})
          [attribute, attribute]
        end

        def maybe_fallback(options={})
          fallback = GlobTagValueNode.new(to_glob(attribute), separator)
          query = fallback.maybe_query(options)
          if query
            QueryExpressionNode.new(query, fallback.condition_values(options))
          else
            nil
          end
        end
      end

      class StringNode < StringExpressionNode
        def initialize(identifier, separator=nil)
          super(identifier, nil, separator)
        end

        def condition(options={})
          "hosts.name = ? OR tags.name = ? OR tags.value = ?"
        end

        def condition_tables(options={})
          [:hosts, :tags]
        end

        def condition_values(options={})
          [identifier, identifier, identifier]
        end

        def maybe_fallback(options={})
          fallback = GlobNode.new(to_glob(identifier), separator)
          query = fallback.maybe_query(options)
          if query
            QueryExpressionNode.new(query, fallback.condition_values(options))
          else
            nil
          end
        end
      end

      class GlobExpressionNode < TagExpressionNode
        def dump(options={})
          data = {}
          data[:identifier_glob] = identifier.to_s if identifier
          data[:separator] = separator.to_s if separator
          data[:attribute_glob] = attribute.to_s if attribute
          data[:fallback] = @fallback.dump(options) if @fallback
          data
        end
      end

      class GlobHostNode < GlobExpressionNode
        def initialize(attribute, separator=nil)
          super("host", attribute, separator)
        end

        def condition(options={})
          "LOWER(hosts.name) GLOB LOWER(?)"
        end

        def condition_tables(options={})
          [:hosts]
        end

        def condition_values(options={})
          [attribute]
        end

        def maybe_fallback(options={})
          fallback = GlobHostNode.new(to_glob(attribute), separator)
          query = fallback.maybe_query(options)
          if query
            QueryExpressionNode.new(query, fallback.condition_values(options))
          else
            nil
          end
        end
      end

      class GlobTagNode < GlobExpressionNode
        def initialize(identifier, attribute, separator=nil)
          super(identifier, attribute, separator)
        end

        def condition(options={})
          "LOWER(tags.name) GLOB LOWER(?) AND LOWER(tags.value) GLOB LOWER(?)"
        end

        def condition_tables(options={})
          [:tags]
        end

        def condition_values(options={})
          [identifier, attribute]
        end

        def maybe_fallback(options={})
          fallback = GlobTagNode.new(to_glob(identifier), to_glob(attribute), separator)
          query = fallback.maybe_query(options)
          if query
            QueryExpressionNode.new(query, fallback.condition_values(options))
          else
            nil
          end
        end
      end

      class GlobTagNameNode < GlobExpressionNode
        def initialize(identifier, separator=nil)
          super(identifier, nil, separator)
        end

        def condition(options={})
          "LOWER(tags.name) GLOB LOWER(?)"
        end

        def condition_tables(options={})
          [:tags]
        end

        def condition_values(options={})
          [identifier]
        end

        def maybe_fallback(options={})
          fallback = GlobTagNameNode.new(to_glob(identifier), separator)
          query = fallback.maybe_query(options)
          if query
            QueryExpressionNode.new(query, fallback.condition_values(options))
          else
            nil
          end
        end
      end

      class GlobTagValueNode < GlobExpressionNode
        def initialize(attribute, separator=nil)
          super(nil, attribute, separator)
        end

        def condition(options={})
          "LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?)"
        end

        def condition_tables(options={})
          [:hosts, :tags]
        end

        def condition_values(options={})
          [attribute, attribute]
        end

        def maybe_fallback(options={})
          fallback = GlobTagValueNode.new(to_glob(attribute), separator)
          query = fallback.maybe_query(options)
          if query
            QueryExpressionNode.new(query, fallback.condition_values(options))
          else
            nil
          end
        end
      end

      class GlobNode < GlobExpressionNode
        def initialize(identifier, separator=nil)
          super(identifier, nil, separator)
        end

        def condition(options={})
          "LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?)"
        end

        def condition_tables(options={})
          [:hosts, :tags]
        end

        def condition_values(options={})
          [identifier, identifier, identifier]
        end

        def maybe_fallback(options={})
          fallback = GlobNode.new(to_glob(identifier), separator)
          query = fallback.maybe_query(options)
          if query
            QueryExpressionNode.new(query, fallback.condition_values(options))
          else
            nil
          end
        end
      end

      class RegexpExpressionNode < TagExpressionNode
        def dump(options={})
          data = {}
          data[:identifier_regexp] = identifier.to_s if identifier
          data[:separator] = separator.to_s if separator
          data[:attribute_regexp] = attribute.to_s if attribute
          data[:fallback] = @fallback.dump(options) if @fallback
          data
        end
      end

      class RegexpHostNode < RegexpExpressionNode
        def initialize(attribute, separator=nil)
          super("host", attribute, separator)
        end

        def condition(options={})
          "hosts.name REGEXP ?"
        end

        def condition_tables(options={})
          [:hosts]
        end

        def condition_values(options={})
          [attribute]
        end
      end

      class RegexpTagNode < RegexpExpressionNode
        def initialize(identifier, attribute, separator=nil)
          super(identifier, attribute, separator)
        end

        def condition(options={})
          "tags.name REGEXP ? AND tags.value REGEXP ?"
        end

        def condition_tables(options={})
          [:tags]
        end

        def condition_values(options={})
          [identifier, attribute]
        end
      end

      class RegexpTagNameNode < RegexpExpressionNode
        def initialize(identifier, separator=nil)
          super(identifier, nil, separator)
        end

        def condition(options={})
          "tags.name REGEXP ?"
        end

        def condition_tables(options={})
          [:tags]
        end

        def condition_values(options={})
          [identifier]
        end
      end

      class RegexpTagValueNode < RegexpExpressionNode
        def initialize(attribute, separator=nil)
          super(nil, attribute, separator)
        end

        def condition(options={})
          "hosts.name REGEXP ? OR tags.value REGEXP ?"
        end

        def condition_tables(options={})
          [:hosts, :tags]
        end

        def condition_values(options={})
          [attribute, attribute]
        end
      end

      class RegexpNode < RegexpExpressionNode
        def initialize(identifier, separator=nil)
          super(identifier, separator)
        end

        def condition(options={})
          "hosts.name REGEXP ? OR tags.name REGEXP ? OR tags.value REGEXP ?"
        end

        def condition_tables(options={})
          [:hosts, :tags]
        end

        def condition_values(options={})
          [identifier, identifier, identifier]
        end
      end
    end
  end
end

# vim:set ft=ruby :
