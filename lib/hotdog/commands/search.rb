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

      def evaluate(data, environment)
        node = ExpressionTransformer.new.apply(data)
        optimized = node.optimize.tap do |optimized|
          logger.debug(JSON.pretty_generate(optimized.dump))
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
          | spacing.maybe >> identifier_regexp.as(:identifier_regexp) >> separator.as(:separator) >> attribute_regexp.as(:attribute_regexp) >> spacing.maybe \
          | spacing.maybe >> identifier_regexp.as(:identifier_regexp) >> separator.as(:separator) >> spacing.maybe \
          | spacing.maybe >> identifier_regexp.as(:identifier_regexp) >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> separator.as(:separator) >> attribute_glob.as(:attribute_glob) >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> separator.as(:separator) >> attribute.as(:attribute) >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> separator.as(:separator) >> spacing.maybe \
          | spacing.maybe >> identifier_glob.as(:identifier_glob) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier) >> separator.as(:separator) >> attribute_glob.as(:attribute_glob) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier) >> separator.as(:separator) >> attribute.as(:attribute) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier) >> separator.as(:separator) >> spacing.maybe \
          | spacing.maybe >> identifier.as(:identifier) >> spacing.maybe \
          | spacing.maybe >> separator.as(:separator) >> attribute_regexp.as(:attribute_regexp) >> spacing.maybe \
          | spacing.maybe >> separator.as(:separator) >> attribute_glob.as(:attribute_glob) >> spacing.maybe \
          | spacing.maybe >> separator.as(:separator) >> attribute.as(:attribute) >> spacing.maybe \
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
          ( str('/') >> (str('/').absent? >> any).repeat(0) >> str('/') \
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
          TagRegexpExpressionNode.new(identifier_regexp.to_s, attribute_regexp.to_s, separator)
        }
        rule(identifier_regexp: simple(:identifier_regexp), separator: simple(:separator)) {
          TagRegexpExpressionNode.new(identifier_regexp.to_s, nil, nil)
        }
        rule(identifier_regexp: simple(:identifier_regexp)) {
          TagRegexpExpressionNode.new(identifier_regexp.to_s, nil, nil)
        }
        rule(identifier_glob: simple(:identifier_glob), separator: simple(:separator), attribute_glob: simple(:attribute_glob)) {
          TagGlobExpressionNode.new(identifier_glob.to_s, attribute_glob.to_s, separator)
        }
        rule(identifier_glob: simple(:identifier_glob), separator: simple(:separator), attribute: simple(:attribute)) {
          TagGlobExpressionNode.new(identifier_glob.to_s, attribute.to_s, separator)
        }
        rule(identifier_glob: simple(:identifier_glob), separator: simple(:separator)) {
          TagGlobExpressionNode.new(identifier_glob.to_s, nil, separator)
        }
        rule(identifier_glob: simple(:identifier_glob)) {
          TagGlobExpressionNode.new(identifier_glob.to_s, nil, nil)
        }
        rule(identifier: simple(:identifier), separator: simple(:separator), attribute_glob: simple(:attribute_glob)) {
          TagGlobExpressionNode.new(identifier.to_s, attribute_glob.to_s, separator)
        }
        rule(identifier: simple(:identifier), separator: simple(:separator), attribute: simple(:attribute)) {
          TagExpressionNode.new(identifier.to_s, attribute.to_s, separator)
        }
        rule(identifier: simple(:identifier), separator: simple(:separator)) {
          TagExpressionNode.new(identifier.to_s, nil, separator)
        }
        rule(identifier: simple(:identifier)) {
          TagExpressionNode.new(identifier.to_s, nil, nil)
        }
        rule(separator: simple(:separator), attribute_regexp: simple(:attribute_regexp)) {
          TagRegexpExpressionNode.new(nil, attribute_regexp.to_s, separator)
        }
        rule(attribute_regexp: simple(:attribute_regexp)) {
          TagRegexpExpressionNode.new(nil, attribute_regexp.to_s, nil)
        }
        rule(separator: simple(:separator), attribute_glob: simple(:attribute_glob)) {
          TagGlobExpressionNode.new(nil, attribute_glob.to_s, separator)
        }
        rule(attribute_glob: simple(:attribute_glob)) {
          TagGlobExpressionNode.new(nil, attribute_glob.to_s, nil)
        }
        rule(separator: simple(:separator), attribute: simple(:attribute)) {
          TagExpressionNode.new(nil, attribute.to_s, separator)
        }
        rule(attribute: simple(:attribute)) {
          TagExpressionNode.new(nil, attribute.to_s, nil)
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
              optimize1(options)
            end
          when :XOR
            optimize1(options)
          else
            self
          end
        end

        def ==(other)
          self.class === other and @op == other.op and @left == other.left and @right == other.right
        end

        def dump(options={})
          {left: @left.dump(options), op: @op.to_s, right: @right.dump(options)}
        end

        private
        def optimize1(options)
          if TagExpressionNode === left and TagExpressionNode === right
            lhs = left.plan(options)
            rhs = right.plan(options)
            if lhs and rhs and lhs[1].length + rhs[1].length <= SQLITE_LIMIT_COMPOUND_SELECT
              case op
              when :AND
                q = "SELECT host_id FROM ( #{lhs[0].sub(/\s*;\s*\z/, "")} ) " \
                      "INTERSECT #{rhs[0].sub(/\s*;\s*\z/, "")};"
                QueryExpressionNode.new(q, lhs[1] + rhs[1], fallback: self)
              when :OR
                q = "SELECT host_id FROM ( #{lhs[0].sub(/\s*;\s*\z/, "")} ) " \
                      "UNION #{rhs[0].sub(/\s*;\s*\z/, "")};"
                QueryExpressionNode.new(q, lhs[1] + rhs[1], fallback: self)
              when :XOR
                q = "SELECT host_id FROM ( #{lhs[0].sub(/\s*;\s*\z/, "")} ) " \
                      "UNION #{rhs[0].sub(/\s*;\s*\z/, "")} " \
                      "EXCEPT SELECT host_id FROM ( #{lhs[0].sub(/\s*;\s*\z/, "")} ) " \
                        "INTERSECT #{rhs[0].sub(/\s*;\s*\z/, "")};"
                QueryExpressionNode.new(q, lhs[1] + rhs[1], fallback: self)
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
          {op: @op.to_s, expression: @expression.dump(options)}
        end

        private
        def optimize1(options={})
          case op
          when :NOT
            if UnaryExpressionNode === expression and expression.op == :NOT
              expression.expression
            else
              if TagExpressionNode === expression
                expr = expression.plan(options)
                if expr and expr[1].length <= SQLITE_LIMIT_COMPOUND_SELECT
                  q = "SELECT id AS host_id FROM hosts " \
                        "EXCEPT #{expr[0].sub(/\s*;\s*\z/, "")};"
                  QueryExpressionNode.new(q, expr[1])
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

      class QueryExpressionNode < ExpressionNode
        def initialize(query, args=[], options={})
          @query = query
          @args = args
          @fallback = options[:fallback]
        end

        def evaluate(environment, options={})
          values = environment.execute(@query, @args).map { |row| row.first }
          if values.empty? and @fallback
            @fallback.evaluate(environment, options)
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

        def plan(options={})
          if identifier?
            if attribute?
              case identifier
              when /\Ahost\z/i
                q = "SELECT hosts.id AS host_id FROM hosts " \
                      "WHERE hosts.name = ?;"
                [q, [attribute]]
              else
                q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                      "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                        "WHERE tags.name = ? AND tags.value = ?;"
                [q, [identifier, attribute]]
              end
            else
              if separator?
                q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                      "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                        "WHERE tags.name = ?;"
                [q, [identifier]]
              else
                q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                      "INNER JOIN hosts ON hosts_tags.host_id = hosts.id " \
                      "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                        "WHERE hosts.name = ? OR tags.name = ? OR tags.value = ?;"
                [q, [identifier, identifier, identifier]]
              end
            end
          else
            if attribute?
               q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                     "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                       "WHERE tags.value = ?;"
              [q, [attribute]]
            else
              nil
            end
          end
        end

        def evaluate(environment, options={})
          if q = plan(options)
            values = environment.execute(*q).map { |row| row.first }
            if values.empty?
              if options[:did_fallback]
                []
              else
                if not environment.fixed_string? and @fallback
                  # avoid optimizing @fallback to prevent infinite recursion
                  values = @fallback.evaluate(environment, options.merge(did_fallback: true))
                  if values.empty?
                    reload(environment, options)
                  else
                    values
                  end
                else
                  reload(environment, options)
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
          if identifier?
            prefix = (identifier.start_with?("*")) ? "" : "*"
            suffix = (identifier.end_with?("*")) ? "" : "*"
            identifier_glob = prefix + identifier.gsub(/[-.\/_]/, "?") + suffix
          else
            identifier_glob = nil
          end
          if attribute?
            prefix = (attribute.start_with?("*")) ? "" : "*"
            suffix = (attribute.end_with?("*")) ? "" : "*"
            attribute_glob = prefix + attribute.gsub(/[-.\/_]/, "?") + suffix
          else
            attribute_glob = nil
          end
          if (identifier? and identifier != identifier_glob) or (attribute? and attribute != attribute_glob)
            @fallback = TagGlobExpressionNode.new(identifier_glob, attribute_glob, separator)
          end
          self
        end

        def reload(environment, options={})
          ttl = options.fetch(:ttl, 1)
          if 0 < ttl
            environment.logger.info("force reloading all hosts and tags.")
            environment.reload(force: true)
            self.class.new(identifier, attribute, separator).optimize(options).evaluate(environment, options.merge(ttl: ttl-1))
          else
            []
          end
        end

        def dump(options={})
          data = {}
          data[:identifier] = @identifier.to_s if @identifier
          data[:separator] = @separator.to_s if @separator
          data[:attribute] = @attribute.to_s if @attribute
          data[:fallback ] = @fallback.dump(options) if @fallback
          data
        end
      end

      class TagGlobExpressionNode < TagExpressionNode
        def plan(options={})
          if identifier?
            if attribute?
              case identifier
              when /\Ahost\z/i
                q = "SELECT hosts.id AS host_id FROM hosts " \
                      "WHERE LOWER(hosts.name) GLOB LOWER(?);"
                [q, [attribute]]
              else
                q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                      "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                        "WHERE LOWER(tags.name) GLOB LOWER(?) AND LOWER(tags.value) GLOB LOWER(?);"
                [q, [identifier, attribute]]
              end
            else
              if separator?
                q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                      "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                        "WHERE LOWER(tags.name) GLOB LOWER(?);"
                [q, [identifier]]
              else
                q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                      "INNER JOIN hosts ON hosts_tags.host_id = hosts.id " \
                      "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                        "WHERE LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?);"
                [q, [identifier, identifier, identifier]]
              end
            end
          else
            if attribute?
              q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                    "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                      "WHERE LOWER(tags.value) GLOB LOWER(?);"
              [q, [attribute]]
            else
              nil
            end
          end
        end

        def dump(options={})
          data = {}
          data[:identifier_glob] = @identifier.to_s if @identifier
          data[:separator] = @separator.to_s if @separator
          data[:attribute_glob] = @attribute.to_s if @attribute
          data[:fallback] = @fallback.dump(options) if @fallback
          data
        end
      end

      class TagRegexpExpressionNode < TagExpressionNode
        def initialize(identifier, attribute, separator=nil)
          identifier = identifier.sub(%r{\A/(.*)/\z}) { $1 } if identifier
          attribute = attribute.sub(%r{\A/(.*)/\z}) { $1 } if attribute
          super(identifier, attribute, separator)
        end

        def plan(options={})
          if identifier?
            if attribute?
              case identifier
              when /\Ahost\z/i
                q = "SELECT hosts.id AS host_id FROM hosts " \
                      "WHERE hosts.name REGEXP ?;"
                [q, [attribute]]
              else
                q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                      "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                        "WHERE tags.name REGEXP ? AND tags.value REGEXP ?;"
                [q, [identifier, attribute]]
              end
            else
              if separator?
                q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                      "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                        "WHERE tags.name REGEXP ?;"
                [q, [identifier]]
              else
                q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                      "INNER JOIN hosts ON hosts_tags.host_id = hosts.id " \
                      "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                        "WHERE hosts.name REGEXP ? OR tags.name REGEXP ? OR tags.value REGEXP ?;"
                [q, [identifier, identifier, identifier]]
              end
            end
          else
            if attribute?
              q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                    "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                      "WHERE tags.value REGEXP ?;"
              [q, [attribute]]
            else
              nil
            end
          end
        end

        def optimize(options={})
          self # disable fallback
        end

        def dump(options={})
          data = {}
          data[:identifier_regexp] = @identifier.to_s if @identifier
          data[:separator] = @separator.to_s if @separator
          data[:attribute_regexp] = @attribute.to_s if @attribute
          data[:fallback] = @fallback.dump(options) if @fallback
          data
        end
      end
    end
  end
end

# vim:set ft=ruby :
