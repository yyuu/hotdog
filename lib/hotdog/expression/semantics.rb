#!/usr/bin/env ruby

module Hotdog
  module Expression
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
    end

    class UnaryExpressionNode < ExpressionNode
      attr_reader :op, :expression

      def initialize(op, expression)
        case (op || "not").to_s
        when "!", "~", "NOT", "not"
          @op = :NOT
        else
          raise(SyntaxError.new("unknown unary operator: #{op.inspect}"))
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
            min, max = environment.execute("SELECT MIN(id), MAX(id) FROM hosts LIMIT 1;").first.to_a
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
              min, max = environment.execute("SELECT MIN(id), MAX(id) FROM hosts LIMIT 1;").first.to_a
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
              min, max = environment.execute("SELECT MIN(id), MAX(id) FROM hosts LIMIT 1;").first.to_a
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
              min, max = environment.execute("SELECT MIN(id), MAX(id) FROM hosts LIMIT 1;").first.to_a
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
            right
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

    class FuncallNode < ExpressionNode
      attr_reader :function, :args

      def initialize(function, args)
        # FIXME: smart argument handling (e.g. arity & type checking)
        case function.to_s
        when "HEAD", "head"
          @function = :HEAD
        when "GROUP_BY", "group_by"
          @function = :GROUP_BY
        when "LIMIT", "limit"
          @function = :HEAD
        when "ORDER_BY", "order_by"
          @function = :ORDER_BY
        when "REVERSE", "reverse"
          @function = :REVERSE
        when "SAMPLE", "sample"
          @function = :HEAD
          args[0] = FuncallNode.new("SHUFFLE", [args[0]])
        when "SHUFFLE", "shuffle"
          @function = :SHUFFLE
        when "SLICE", "slice"
          @function = :SLICE
        when "SORT", "sort"
          @function = :ORDER_BY
        when "TAIL", "tail"
          @function = :TAIL
        else
          raise(SyntaxError.new("unknown function call: #{function}"))
        end
        @args = args
      end

      def dump(options={})
        args = @args.map { |arg|
          if ExpressionNode === arg
            arg.dump(options)
          else
            arg
          end
        }
        {funcall: @function.to_s, args: args}
      end

      def optimize(options={})
        case function
        when :HEAD
          @args[0] = @args[0].optimize(options)
        when :GROUP_BY
          @args[0] = @args[0].optimize(options)
          if TagExpressionNode === args[1]
            # workaround for expressions like `ORDER_BY((environment:development),role)`
            @args[1] = @args[1].tag_name
          else
            @args[1] = @args[1]
          end
        when :ORDER_BY
          @args[0] = @args[0].optimize(options)
          if @args[1]
            if TagExpressionNode === @args[1]
              # workaround for expressions like `ORDER_BY((environment:development),role)`
              @args[1] = @args[1].tag_name
            else
              @args[1] = @args[1]
            end
          end
        when :REVERSE
          @args[0] = @args[0].optimize(options)
        when :SHUFFLE
          @args[0] = @args[0].optimize(options)
        when :SLICE
          @args[0] = @args[0].optimize(options)
        when :TAIL
          @args[0] = @args[0].optimize(options)
        end
        self
      end

      def evaluate(environment, options={})
        case function
        when :HEAD
          args[0].evaluate(environment, options).take(args[1] || 1)
        when :GROUP_BY
          intermediate = args[0].evaluate(environment, options)
          q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                "WHERE tags.name = ? AND hosts_tags.host_id IN (%s) " \
                "GROUP BY tags.value;" % intermediate.map { "?" }.join(", ")
          QueryExpressionNode.new(q, [args[1]] + intermediate, fallback: nil).evaluate(environment, options)
        when :ORDER_BY
          intermediate = args[0].evaluate(environment, options)
          if args[1]
            q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                  "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                  "WHERE tags.name = ? AND hosts_tags.host_id IN (%s) " \
                  "ORDER BY tags.value;" % intermediate.map { "?" }.join(", ")
            QueryExpressionNode.new(q, [args[1]] + intermediate, fallback: nil).evaluate(environment, options)
          else
            q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                  "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                  "WHERE hosts_tags.host_id IN (%s) " \
                  "ORDER BY hosts_tags.host_id;" % intermediate.map { "?" }.join(", ")
            QueryExpressionNode.new(q, intermediate, fallback: nil).evaluate(environment, options)
          end
        when :REVERSE
          args[0].evaluate(environment, options).reverse()
        when :SHUFFLE
          args[0].evaluate(environment, options).shuffle()
        when :SLICE
          args[0].evaluate(environment, options).slice(args[1], args[2] || 1)
        when :TAIL
          args[0].evaluate(environment, options).last(args[1] || 1)
        else
          []
        end
      end
    end

    class EverythingNode < QueryExpressionNode
      def initialize(options={})
        super("SELECT id AS host_id FROM hosts;", [], options)
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
      def initialize(tag_name, tag_value, separator=nil)
        @tag_name = tag_name
        @tag_value = tag_value
        @separator = separator
        @fallback = nil
      end
      attr_reader :tag_name
      attr_reader :tag_value
      attr_reader :separator

      def tag_name?
        !(tag_name.nil? or tag_name.to_s.empty?)
      end

      def tag_value?
        !(tag_value.nil? or tag_value.to_s.empty?)
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
        self.class == other.class and @tag_name == other.tag_name and @tag_value == other.tag_value
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
        data[:tag_name] = tag_name.to_s if tag_name
        data[:separator] = separator.to_s if separator
        data[:tag_value] = tag_value.to_s if tag_value
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
      def initialize(tag_value, separator=nil)
        super("host", tag_value.to_s, separator)
      end

      def condition(options={})
        "hosts.name = ?"
      end

      def condition_tables(options={})
        [:hosts]
      end

      def condition_values(options={})
        [tag_value]
      end

      def maybe_fallback(options={})
        fallback = GlobHostNode.new(to_glob(tag_value), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class StringTagNode < StringExpressionNode
      def initialize(tag_name, tag_value, separator=nil)
        super(tag_name.to_s, tag_value.to_s, separator)
      end

      def condition(options={})
        "tags.name = ? AND tags.value = ?"
      end

      def condition_tables(options={})
        [:tags]
      end

      def condition_values(options={})
        [tag_name, tag_value]
      end

      def maybe_fallback(options={})
        fallback = GlobTagNode.new(to_glob(tag_name), to_glob(tag_value), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class StringTagNameNode < StringExpressionNode
      def initialize(tag_name, separator=nil)
        super(tag_name.to_s, nil, separator)
      end

      def condition(options={})
        "tags.name = ?"
      end

      def condition_tables(options={})
        [:tags]
      end

      def condition_values(options={})
        [tag_name]
      end

      def maybe_fallback(options={})
        fallback = GlobTagNameNode.new(to_glob(tag_name), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class StringTagValueNode < StringExpressionNode
      def initialize(tag_value, separator=nil)
        super(nil, tag_value.to_s, separator)
      end

      def condition(options={})
        "hosts.name = ? OR tags.value = ?"
      end

      def condition_tables(options={})
        [:hosts, :tags]
      end

      def condition_values(options={})
        [tag_value, tag_value]
      end

      def maybe_fallback(options={})
        fallback = GlobTagValueNode.new(to_glob(tag_value), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class StringNode < StringExpressionNode
      def initialize(tag_name, separator=nil)
        super(tag_name.to_s, nil, separator)
      end

      def condition(options={})
        "hosts.name = ? OR tags.name = ? OR tags.value = ?"
      end

      def condition_tables(options={})
        [:hosts, :tags]
      end

      def condition_values(options={})
        [tag_name, tag_name, tag_name]
      end

      def maybe_fallback(options={})
        fallback = GlobNode.new(to_glob(tag_name), separator)
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
        data[:tag_name_glob] = tag_name.to_s if tag_name
        data[:separator] = separator.to_s if separator
        data[:tag_value_glob] = tag_value.to_s if tag_value
        data[:fallback] = @fallback.dump(options) if @fallback
        data
      end
    end

    class GlobHostNode < GlobExpressionNode
      def initialize(tag_value, separator=nil)
        super("host", tag_value.to_s, separator)
      end

      def condition(options={})
        "LOWER(hosts.name) GLOB LOWER(?)"
      end

      def condition_tables(options={})
        [:hosts]
      end

      def condition_values(options={})
        [tag_value]
      end

      def maybe_fallback(options={})
        fallback = GlobHostNode.new(to_glob(tag_value), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class GlobTagNode < GlobExpressionNode
      def initialize(tag_name, tag_value, separator=nil)
        super(tag_name.to_s, tag_value.to_s, separator)
      end

      def condition(options={})
        "LOWER(tags.name) GLOB LOWER(?) AND LOWER(tags.value) GLOB LOWER(?)"
      end

      def condition_tables(options={})
        [:tags]
      end

      def condition_values(options={})
        [tag_name, tag_value]
      end

      def maybe_fallback(options={})
        fallback = GlobTagNode.new(to_glob(tag_name), to_glob(tag_value), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class GlobTagNameNode < GlobExpressionNode
      def initialize(tag_name, separator=nil)
        super(tag_name.to_s, nil, separator)
      end

      def condition(options={})
        "LOWER(tags.name) GLOB LOWER(?)"
      end

      def condition_tables(options={})
        [:tags]
      end

      def condition_values(options={})
        [tag_name]
      end

      def maybe_fallback(options={})
        fallback = GlobTagNameNode.new(to_glob(tag_name), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class GlobTagValueNode < GlobExpressionNode
      def initialize(tag_value, separator=nil)
        super(nil, tag_value.to_s, separator)
      end

      def condition(options={})
        "LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?)"
      end

      def condition_tables(options={})
        [:hosts, :tags]
      end

      def condition_values(options={})
        [tag_value, tag_value]
      end

      def maybe_fallback(options={})
        fallback = GlobTagValueNode.new(to_glob(tag_value), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class GlobNode < GlobExpressionNode
      def initialize(tag_name, separator=nil)
        super(tag_name.to_s, nil, separator)
      end

      def condition(options={})
        "LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?)"
      end

      def condition_tables(options={})
        [:hosts, :tags]
      end

      def condition_values(options={})
        [tag_name, tag_name, tag_name]
      end

      def maybe_fallback(options={})
        fallback = GlobNode.new(to_glob(tag_name), separator)
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
        data[:tag_name_regexp] = tag_name.to_s if tag_name
        data[:separator] = separator.to_s if separator
        data[:tag_value_regexp] = tag_value.to_s if tag_value
        data[:fallback] = @fallback.dump(options) if @fallback
        data
      end
    end

    class RegexpHostNode < RegexpExpressionNode
      def initialize(tag_value, separator=nil)
        case tag_value
        when /\A\/(.*)\/\z/
          tag_value = $1
        end
        super("host", tag_value, separator)
      end

      def condition(options={})
        "hosts.name REGEXP ?"
      end

      def condition_tables(options={})
        [:hosts]
      end

      def condition_values(options={})
        [tag_value]
      end
    end

    class RegexpTagNode < RegexpExpressionNode
      def initialize(tag_name, tag_value, separator=nil)
        case tag_name
        when /\A\/(.*)\/\z/
          tag_name = $1
        end
        case tag_value
        when /\A\/(.*)\/\z/
          tag_value = $1
        end
        super(tag_name, tag_value, separator)
      end

      def condition(options={})
        "tags.name REGEXP ? AND tags.value REGEXP ?"
      end

      def condition_tables(options={})
        [:tags]
      end

      def condition_values(options={})
        [tag_name, tag_value]
      end
    end

    class RegexpTagNameNode < RegexpExpressionNode
      def initialize(tag_name, separator=nil)
        case tag_name
        when /\A\/(.*)\/\z/
          tag_name = $1
        end
        super(tag_name.to_s, nil, separator)
      end

      def condition(options={})
        "tags.name REGEXP ?"
      end

      def condition_tables(options={})
        [:tags]
      end

      def condition_values(options={})
        [tag_name]
      end
    end

    class RegexpTagValueNode < RegexpExpressionNode
      def initialize(tag_value, separator=nil)
        case tag_value
        when /\A\/(.*)\/\z/
          tag_value = $1
        end
        super(nil, tag_value.to_s, separator)
      end

      def condition(options={})
        "hosts.name REGEXP ? OR tags.value REGEXP ?"
      end

      def condition_tables(options={})
        [:hosts, :tags]
      end

      def condition_values(options={})
        [tag_value, tag_value]
      end
    end

    class RegexpNode < RegexpExpressionNode
      def initialize(tag_name, separator=nil)
        super(tag_name, separator)
      end

      def condition(options={})
        "hosts.name REGEXP ? OR tags.name REGEXP ? OR tags.value REGEXP ?"
      end

      def condition_tables(options={})
        [:hosts, :tags]
      end

      def condition_values(options={})
        [tag_name, tag_name, tag_name]
      end
    end
  end
end

# vim:set ft=ruby :
