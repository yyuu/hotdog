#!/usr/bin/env ruby

require "json"
require "parslet"

module Hotdog
  module Commands
    class Search < BaseCommand
      def define_options(optparse)
        @search_options = @options.merge({
        })
        optparse.on("-n", "--limit LIMIT", "Limit result set to specified size at most", Integer) do |limit|
          @search_options[:limit] = limit
        end
      end

      def run(args=[])
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

        result = evaluate(node, self)
        if 0 < result.length
          _result, fields = get_hosts_with_search_tags(result, node)
          result = _result.take(@search_options.fetch(:limit, _result.size))
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
          ( unary_op.as(:unary_op) >> spacing.maybe >> expression.as(:expression) \
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
          )
        }
        rule(:identifier) {
          ( binary_op.absent? >> unary_op.absent? >> match('[A-Za-z]') >> match('[-./0-9A-Z_a-z]').repeat(0) \
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
          )
        }
        rule(:attribute) {
          ( binary_op.absent? >> unary_op.absent? >> match('[-./0-9:A-Z_a-z]').repeat(1) \
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
          RegexpTagNameNode.new(identifier_regexp.to_s, separator)
        }
        rule(identifier_regexp: simple(:identifier_regexp)) {
          RegexpNode.new(identifier_regexp.to_s)
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
          GlobTagNameNode.new(identifier_glob.to_s, separator)
        }
        rule(identifier_glob: simple(:identifier_glob)) {
          GlobNode.new(identifier_glob.to_s)
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
          StringTagNameNode.new(identifier.to_s, separator)
        }
        rule(identifier: simple(:identifier)) {
          StringNode.new(identifier.to_s)
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
          raise(NotImplementedError)
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
          case op
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
              environment.execute("SELECT id FROM hosts").map { |row| row.first }.tap do |values|
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
            optimize1(options)
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
              if TagExpressionNode === expression
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
          case op || "or"
          when "&&", "&", /\Aand\z/i
            @op = :AND
          when "||", "|", /\Aor\z/i
            @op = :OR
          when "^", /\Axor\z/i
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
            if left == right
              left
            else
              optimize1(options)
            end
          when :OR
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
          case op
          when :OR
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
              if query_without_condition = expressions.first.maybe_query_without_condition(options)
                q = query_without_condition.sub(/\s*;\s*\z/, "") + " WHERE " + expressions.map { |expression| "( %s )" % expression.condition(options) }.join(" OR ") + ";"
                condition_length = expressions.first.condition_values(options).length
                values = expressions.each_slice(SQLITE_LIMIT_COMPOUND_SELECT / condition_length).flat_map { |expressions|
                  environment.execute(q, expressions.flat_map { |expression| expression.condition_values(options) }).map { |row| row.first }
                }
              else
                values = []
              end
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

        def dump(optinos={})
          {multinary_op: @op.to_s, expressions: expressions.map { |expression| expression.dump }}
        end

        def intermediates()
          [self] + @expression.flat_map { |expression| expression.intermediates }
        end

        def leafs()
          @expressions.flat_map { |expression| expression.leafs }
        end
      end

      class QueryExpressionNode < ExpressionNode
        def initialize(query, args=[], options={})
          @query = query
          @args = args
          @fallback = options[:fallback]
        end

        def evaluate(environment, options={})
          values = environment.execute(@query, @args).map { |row| row.first }
          if values.empty? and @fallback
            @fallback.evaluate(environment, options).tap do |values|
              if values.empty?
                environment.logger.info("no result: #{self.dump.inspect}")
              end
            end
          else
            values
          end
        end

        def dump(options={})
          data = {query: @query, arguments: @args}
          data[:fallback] = @fallback.dump(options) if @fallback
          data
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
          if query_without_condition = maybe_query_without_condition(options)
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
            case tables.sort
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
          raise NotImplementedError
        end

        def condition_tables(options={})
          raise NotImplementedError
        end

        def condition_values(options={})
          raise NotImplementedError
        end

        def evaluate(environment, options={})
          if q = maybe_query(options)
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
          fallback = GlobHostNode.new(maybe_glob(attribute), separator)
          if query = fallback.maybe_query(options)
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
          fallback = GlobTagNode.new(maybe_glob(identifier), maybe_glob(attribute), separator)
          if query = fallback.maybe_query(options)
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
          fallback = GlobTagNameNode.new(maybe_glob(identifier), separator)
          if query = fallback.maybe_query(options)
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
          "tags.value = ?"
        end

        def condition_tables(options={})
          [:tags]
        end

        def condition_values(options={})
          [attribute]
        end

        def maybe_fallback(options={})
          fallback = GlobTagValueNode.new(maybe_glob(attribute), separator)
          if query = fallback.maybe_query(options)
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
          fallback = GlobNode.new(maybe_glob(identifier), separator)
          if query = fallback.maybe_query(options)
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
          fallback = GlobHostNode.new(maybe_glob(attribute), separator)
          if query = fallback.maybe_query(options)
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
          fallback = GlobTagNode.new(maybe_glob(identifier), maybe_glob(attribute), separator)
          if query = fallback.maybe_query(options)
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
          fallback = GlobTagNameNode.new(maybe_glob(identifier), separator)
          if query = fallback.maybe_query(options)
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
          "LOWER(tags.value) GLOB LOWER(?)"
        end

        def condition_tables(options={})
          [:tags]
        end

        def condition_values(options={})
          [attribute]
        end

        def maybe_fallback(options={})
          fallback = GlobTagValueNode.new(maybe_glob(attribute), separator)
          if query = fallback.maybe_query(options)
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
          fallback = GlobNode.new(maybe_glob(identifier), separator).maybe_query(options)
          if query = fallback.maybe_query(options)
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
          "tags.value REGEXP ?"
        end

        def condition_tables(options={})
          [:tags]
        end

        def condition_values(options={})
          [attribute]
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
