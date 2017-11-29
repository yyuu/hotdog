#!/usr/bin/env ruby

module Hotdog
  module Expression
    class ExpressionNode
      def evaluate(environment, options={})
        raise(NotImplementedError.new("must be overridden"))
      end

      def optimize(options={})
        self.dup
      end

      def compact(options={})
        self
      end

      def dump(options={})
        {}
      end

      def ==(other)
        self.dump == other.dump
      end
    end

    class UnaryExpressionNode < ExpressionNode
      attr_reader :op, :expression

      def initialize(op, expression, options={})
        case (op || "not").to_s
        when "NOOP", "noop"
          @op = :NOOP
        when "!", "~", "NOT", "not"
          @op = :NOT
        else
          raise(SyntaxError.new("unknown unary operator: #{op.inspect}"))
        end
        @expression = expression
        @options = {}
      end

      def evaluate(environment, options={})
        case @op
        when :NOOP
          @expression.evaluate(environment, options)
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
            sqlite_limit_compound_select = options[:sqlite_limit_compound_select] || SQLITE_LIMIT_COMPOUND_SELECT
            (min / (sqlite_limit_compound_select - 2)).upto(max / (sqlite_limit_compound_select - 2)).flat_map { |i|
              range = ((sqlite_limit_compound_select - 2) * i)...((sqlite_limit_compound_select - 2) * (i + 1))
              selected = values.select { |n| range === n }
              if 0 < selected.length
                q = "SELECT id FROM hosts " \
                      "WHERE ? <= id AND id < ? AND id NOT IN (%s);"
                environment.execute(q % selected.map { "?" }.join(", "), [range.first, range.last] + selected).map { |row| row.first }
              else
                []
              end
            }.tap do |values|
              environment.logger.debug("NOT expr: #{values.length} value(s)")
            end
          end
        else
          []
        end
      end

      def optimize(options={})
        o_self = compact(options)
        if UnaryExpressionNode === o_self
          case o_self.op
          when :NOT
            case o_self.expression
            when EverythingNode
              NothingNode.new(options)
            when NothingNode
              EverythingNode.new(options)
            else
              o_self.optimize1(options)
            end
          else
            o_self.optimize1(options)
          end
        else
          o_self.optimize(options)
        end
      end

      def compact(options={})
        case op
        when :NOOP
          expression.compact(options)
        else
          UnaryExpressionNode.new(
            op,
            expression.compact(options),
          )
        end
      end

      def ==(other)
        self.class === other and @op == other.op and @expression == other.expression
      end

      def dump(options={})
        {unary_op: @op.to_s, expression: @expression.dump(options)}
      end

      protected
      def optimize1(options={})
        case op
        when :NOOP
          expression.optimize(options)
        when :NOT
          if UnaryExpressionNode === expression
            case expression.op
            when :NOOP
              expression.optimize(options)
            when :NOT
              expression.expression.optimize(options)
            else
              self.dup
            end
          else
            optimize2(options)
          end
        else
          self.dup
        end
      end

      def optimize2(options={})
        sqlite_limit_compound_select = options[:sqlite_limit_compound_select] || SQLITE_LIMIT_COMPOUND_SELECT
        case expression
        when QueryExpressionNode
          q = expression.query
          v = expression.values
          if q and v.length <= sqlite_limit_compound_select
            QueryExpressionNode.new("SELECT id AS host_id FROM hosts EXCEPT #{q.sub(/\s*;\s*\z/, "")};", v)
          else
            self.dup
          end
        when TagExpressionNode
          q = expression.maybe_query(options)
          v = expression.condition_values(options)
          if q and v.length <= sqlite_limit_compound_select
            QueryExpressionNode.new("SELECT id AS host_id FROM hosts EXCEPT #{q.sub(/\s*;\s*\z/, "")};", v)
          else
            self.dup
          end
        else
          self.dup
        end
      end
    end

    class BinaryExpressionNode < ExpressionNode
      attr_reader :op, :left, :right

      def initialize(op, left, right, options={})
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
        @options = {}
      end

      def evaluate(environment, options={})
        case @op
        when :AND
          left_values = @left.evaluate(environment, options).tap do |values|
            environment.logger.debug("lhs(#{values.length})")
          end
          if left_values.empty?
            []
          else
            right_values = @right.evaluate(environment, options).tap do |values|
              environment.logger.debug("rhs(#{values.length})")
            end
            if right_values.empty?
              []
            else
              # workaround for "too many terms in compound SELECT"
              min, max = environment.execute("SELECT MIN(id), MAX(id) FROM hosts LIMIT 1;").first.to_a
              sqlite_limit_compound_select = options[:sqlite_limit_compound_select] || SQLITE_LIMIT_COMPOUND_SELECT
              (min / ((sqlite_limit_compound_select - 2) / 2)).upto(max / ((sqlite_limit_compound_select - 2) / 2)).flat_map { |i|
                range = (((sqlite_limit_compound_select - 2) / 2) * i)...(((sqlite_limit_compound_select - 2) / 2) * (i + 1))
                left_selected = left_values.select { |n| range === n }
                right_selected = right_values.select { |n| range === n }
                if 0 < left_selected.length and 0 < right_selected.length
                  q = "SELECT id FROM hosts " \
                        "WHERE ? <= id AND id < ? AND ( id IN (%s) AND id IN (%s) );"
                  environment.execute(q % [left_selected.map { "?" }.join(", "), right_selected.map { "?" }.join(", ")], [range.first, range.last] + left_selected + right_selected).map { |row| row.first }
                else
                  []
                end
              }.tap do |values|
                environment.logger.debug("lhs(#{left_values.length}) AND rhs(#{right_values.length}) => #{values.length}")
              end
            end
          end
        when :OR
          left_values = @left.evaluate(environment, options).tap do |values|
            environment.logger.debug("lhs(#{values.length})")
          end
          right_values = @right.evaluate(environment, options).tap do |values|
            environment.logger.debug("rhs(#{values.length})")
          end
          if left_values.empty?
            right_values
          else
            if right_values.empty?
              []
            else
              # workaround for "too many terms in compound SELECT"
              min, max = environment.execute("SELECT MIN(id), MAX(id) FROM hosts LIMIT 1;").first.to_a
              sqlite_limit_compound_select = options[:sqlite_limit_compound_select] || SQLITE_LIMIT_COMPOUND_SELECT
              (min / ((sqlite_limit_compound_select - 2) / 2)).upto(max / ((sqlite_limit_compound_select - 2) / 2)).flat_map { |i|
                range = (((sqlite_limit_compound_select - 2) / 2) * i)...(((sqlite_limit_compound_select - 2) / 2) * (i + 1))
                left_selected = left_values.select { |n| range === n }
                right_selected = right_values.select { |n| range === n }
                if 0 < left_selected.length or 0 < right_selected.length
                  q = "SELECT id FROM hosts " \
                        "WHERE ? <= id AND id < ? AND ( id IN (%s) OR id IN (%s) );"
                  environment.execute(q % [left_selected.map { "?" }.join(", "), right_selected.map { "?" }.join(", ")], [range.first, range.last] + left_selected + right_selected).map { |row| row.first }
                else
                  []
                end
              }.tap do |values|
                environment.logger.debug("lhs(#{left_values.length}) OR rhs(#{right_values.length}) => #{values.length}")
              end
            end
          end
        when :XOR
          left_values = @left.evaluate(environment, options).tap do |values|
            environment.logger.debug("lhs(#{values.length})")
          end
          right_values = @right.evaluate(environment, options).tap do |values|
            environment.logger.debug("rhs(#{values.length})")
          end
          if left_values.empty?
            right_values
          else
            if right_values.empty?
              []
            else
              # workaround for "too many terms in compound SELECT"
              min, max = environment.execute("SELECT MIN(id), MAX(id) FROM hosts LIMIT 1;").first.to_a
              sqlite_limit_compound_select = options[:sqlite_limit_compound_select] || SQLITE_LIMIT_COMPOUND_SELECT
              (min / ((sqlite_limit_compound_select - 2) / 4)).upto(max / ((sqlite_limit_compound_select - 2) / 4)).flat_map { |i|
                range = (((sqlite_limit_compound_select - 2) / 4) * i)...(((sqlite_limit_compound_select - 2) / 4) * (i + 1))
                left_selected = left_values.select { |n| range === n }
                right_selected = right_values.select { |n| range === n }
                if 0 < left_selected.length or 0 < right_selected.length
                  q = "SELECT id FROM hosts " \
                        "WHERE ? <= id AND id < ? AND NOT (id IN (%s) AND id IN (%s)) AND ( id IN (%s) OR id IN (%s) );"
                  lq = left_selected.map { "?" }.join(", ")
                  rq = right_selected.map { "?" }.join(", ")
                  environment.execute(q % [lq, rq, lq, rq], [range.first, range.last] + left_selected + right_selected + left_selected + right_selected).map { |row| row.first }
                else
                  []
                end
              }.tap do |values|
                environment.logger.debug("lhs(#{left_values.length}) XOR rhs(#{right_values.length}) => #{values.length}")
              end
            end
          end
        else
          []
        end
      end

      def optimize(options={})
        o_left = @left.optimize(options)
        o_right = @right.optimize(options)
        case op
        when :AND
          case o_left
          when EverythingNode
            o_right
          when NothingNode
            o_left
          else
            if o_left == o_right
              o_left
            else
              BinaryExpressionNode.new(
                op,
                o_left,
                o_right,
              ).optimize1(options)
            end
          end
        when :OR
          case o_left
          when EverythingNode
            o_left
          when NothingNode
            o_right
          else
            if o_left == o_right
              o_left
            else
              if MultinaryExpressionNode === o_left
                if o_left.op == op
                  o_left.merge(o_right, fallback: self)
                else
                  BinaryExpressionNode.new(
                    op,
                    o_left,
                    o_right,
                  ).optimize1(options)
                end
              else
                if MultinaryExpressionNode === o_right
                  if o_right.op == op
                    o_right.merge(o_left, fallback: self)
                  else
                    BinaryExpressionNode.new(
                      op,
                      o_left,
                      o_right,
                    ).optimize1(options)
                  end
                else
                  MultinaryExpressionNode.new(op, [o_left, o_right], fallback: self)
                end
              end
            end
          end
        when :XOR
          if o_left == o_right
            NothingNode.new(options)
          else
            BinaryExpressionNode.new(
              op,
              o_left,
              o_right,
            ).optimize1(options)
          end
        else
          self.dup
        end
      end

      def ==(other)
        self.class === other and @op == other.op and @left == other.left and @right == other.right
      end

      def dump(options={})
        {left: @left.dump(options), binary_op: @op.to_s, right: @right.dump(options)}
      end

      protected
      def optimize1(options)
        if TagExpressionNode === left and TagExpressionNode === right
          lq = left.maybe_query(options)
          lv = left.condition_values(options)
          rq = right.maybe_query(options)
          rv = right.condition_values(options)
          sqlite_limit_compound_select = options[:sqlite_limit_compound_select] || SQLITE_LIMIT_COMPOUND_SELECT
          if lq and rq and lv.length + rv.length <= sqlite_limit_compound_select
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
              self.dup
            end
          else
            self.dup
          end
        else
          self.dup
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
        sqlite_limit_compound_select = options[:sqlite_limit_compound_select] || SQLITE_LIMIT_COMPOUND_SELECT
        if sqlite_limit_compound_select < expressions.length
          raise(ArgumentError.new("expressions limit exceeded: #{expressions.length} for #{sqlite_limit_compound_select}"))
        end
        @expressions = expressions
        @options = options
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
                sqlite_limit_compound_select = options[:sqlite_limit_compound_select] || SQLITE_LIMIT_COMPOUND_SELECT
                expressions.each_slice(sqlite_limit_compound_select / condition_length).flat_map { |expressions|
                  q = query_without_condition.sub(/\s*;\s*\z/, " WHERE #{expressions.map { |expression| "( %s )" % expression.condition(options) }.join(" OR ")};")
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
          if @options[:fallback]
            @options[:fallback].evaluate(environment, options={})
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
        @options = options
      end
      attr_reader :query
      attr_reader :values

      def evaluate(environment, options={})
        values = environment.execute(@query, @values).map { |row| row.first }
        if values.empty? and @options[:fallback]
          @options[:fallback].evaluate(environment, options)
        else
          values
        end
      end

      def dump(options={})
        data = {query: @query, values: @values}
        data[:fallback] = @options[:fallback].dump(options) if @options[:fallback]
        data
      end
    end

    class FuncallNode < ExpressionNode
      attr_reader :function, :args

      def initialize(function, args, options={})
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
        @options = options
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
        when :GROUP_BY
          o_args = [@args[0].optimize(options)]
          if TagExpressionNode === args[1]
            # workaround for expressions like `ORDER_BY((environment:development),role)`
            o_args << @args[1].tagname
          else
            o_args << @args[1]
          end
        when :ORDER_BY
          o_args = [@args[0].optimize(options)]
          if @args[1]
            if TagExpressionNode === @args[1]
              # workaround for expressions like `ORDER_BY((environment:development),role)`
              o_args << @args[1].tagname
            else
              o_args << @args[1]
            end
          end
        else
          o_args = @args.map { |arg|
            if ExpressionNode === arg
              arg.optimize(options)
            else
              arg
            end
          }
        end
        FuncallNode.new(
          @function,
          o_args,
        )
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
          QueryExpressionNode.new(q, [args[1]] + intermediate).evaluate(environment, options)
        when :ORDER_BY
          intermediate = args[0].evaluate(environment, options)
          if args[1]
            q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                  "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                  "WHERE tags.name = ? AND hosts_tags.host_id IN (%s) " \
                  "ORDER BY tags.value;" % intermediate.map { "?" }.join(", ")
            QueryExpressionNode.new(q, [args[1]] + intermediate).evaluate(environment, options)
          else
            q = "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags " \
                  "INNER JOIN tags ON hosts_tags.tag_id = tags.id " \
                  "WHERE hosts_tags.host_id IN (%s) " \
                  "ORDER BY hosts_tags.host_id;" % intermediate.map { "?" }.join(", ")
            QueryExpressionNode.new(q, intermediate).evaluate(environment, options)
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
        super("SELECT NULL AS host_id WHERE host_id NOT NULL;", [], options)
      end
    end

    class TagExpressionNode < ExpressionNode
      def initialize(tagname, tagvalue, separator=nil, options={})
        @tagname = tagname
        @tagvalue = tagvalue
        @separator = separator
        @options = options
      end
      attr_reader :tagname
      attr_reader :tagvalue
      attr_reader :separator

      def tagname?
        !(tagname.nil? or tagname.to_s.empty?)
      end

      def tagvalue?
        !(tagvalue.nil? or tagvalue.to_s.empty?)
      end

      def separator?
        !(separator.nil? or separator.to_s.empty?)
      end

      def maybe_query(options={})
        query_without_condition = maybe_query_without_condition(options)
        if query_without_condition
          query_without_condition.sub(/\s*;\s*\z/, " WHERE #{condition(options)};")
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
              if not environment.fixed_string? and @options[:fallback]
                # avoid optimizing @options[:fallback] to prevent infinite recursion
                @options[:fallback].evaluate(environment, options.merge(did_fallback: true))
              else
                []
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
        self.class == other.class and @tagname == other.tagname and @tagvalue == other.tagvalue
      end

      def optimize(options={})
        # fallback to glob expression
        self.dup.tap do |o_self|
          o_self.instance_eval {
            @options[:fallback] ||= maybe_fallback(options)
          }
        end
      end

      def to_glob(s)
        (s.start_with?("*") ? "" : "*") + s.gsub(/[-.\/_]/, "?") + (s.end_with?("*") ? "" : "*")
      end

      def maybe_glob(s)
        s ? to_glob(s.to_s) : nil
      end

      def dump(options={})
        data = {}
        data[:tagname] = tagname.to_s if tagname
        data[:separator] = separator.to_s if separator
        data[:tagvalue] = tagvalue.to_s if tagvalue
        data[:fallback] = @options[:fallback].dump(options) if @options[:fallback]
        data
      end

      def maybe_fallback(options={})
        nil
      end
    end

    class AnyHostNode < TagExpressionNode
      def initialize(separator=nil, options={})
        super("@host", nil, separator, options)
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
      def initialize(tagvalue, separator=nil, options={})
        super("@host", tagvalue.to_s, separator, options)
      end

      def condition(options={})
        "hosts.name = ?"
      end

      def condition_tables(options={})
        [:hosts]
      end

      def condition_values(options={})
        [tagvalue]
      end

      def maybe_fallback(options={})
        fallback = GlobHostNode.new(to_glob(tagvalue), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class StringTagNode < StringExpressionNode
      def initialize(tagname, tagvalue, separator=nil, options={})
        super(tagname.to_s, tagvalue.to_s, separator, options)
      end

      def condition(options={})
        "tags.name = ? AND tags.value = ?"
      end

      def condition_tables(options={})
        [:tags]
      end

      def condition_values(options={})
        [tagname, tagvalue]
      end

      def maybe_fallback(options={})
        fallback = GlobTagNode.new(to_glob(tagname), to_glob(tagvalue), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class StringTagnameNode < StringExpressionNode
      def initialize(tagname, separator=nil, options={})
        super(tagname.to_s, nil, separator, options)
      end

      def condition(options={})
        "tags.name = ?"
      end

      def condition_tables(options={})
        [:tags]
      end

      def condition_values(options={})
        [tagname]
      end

      def maybe_fallback(options={})
        fallback = GlobTagnameNode.new(to_glob(tagname), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class StringTagvalueNode < StringExpressionNode
      def initialize(tagvalue, separator=nil, options={})
        super(nil, tagvalue.to_s, separator, options)
      end

      def condition(options={})
        "hosts.name = ? OR tags.value = ?"
      end

      def condition_tables(options={})
        [:hosts, :tags]
      end

      def condition_values(options={})
        [tagvalue, tagvalue]
      end

      def maybe_fallback(options={})
        fallback = GlobTagvalueNode.new(to_glob(tagvalue), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class StringHostOrTagNode < StringExpressionNode
      def initialize(tagname, separator=nil, options={})
        super(tagname.to_s, nil, separator, options)
      end

      def condition(options={})
        "hosts.name = ? OR tags.name = ? OR tags.value = ?"
      end

      def condition_tables(options={})
        [:hosts, :tags]
      end

      def condition_values(options={})
        [tagname, tagname, tagname]
      end

      def maybe_fallback(options={})
        fallback = GlobHostOrTagNode.new(to_glob(tagname), separator)
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
        data[:tagname_glob] = tagname.to_s if tagname
        data[:separator] = separator.to_s if separator
        data[:tagvalue_glob] = tagvalue.to_s if tagvalue
        data[:fallback] = @options[:fallback].dump(options) if @options[:fallback]
        data
      end
    end

    class GlobHostNode < GlobExpressionNode
      def initialize(tagvalue, separator=nil, options={})
        super("@host", tagvalue.to_s, separator, options)
      end

      def condition(options={})
        "LOWER(hosts.name) GLOB LOWER(?)"
      end

      def condition_tables(options={})
        [:hosts]
      end

      def condition_values(options={})
        [tagvalue]
      end

      def maybe_fallback(options={})
        fallback = GlobHostNode.new(to_glob(tagvalue), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class GlobTagNode < GlobExpressionNode
      def initialize(tagname, tagvalue, separator=nil, options={})
        super(tagname.to_s, tagvalue.to_s, separator, options)
      end

      def condition(options={})
        "LOWER(tags.name) GLOB LOWER(?) AND LOWER(tags.value) GLOB LOWER(?)"
      end

      def condition_tables(options={})
        [:tags]
      end

      def condition_values(options={})
        [tagname, tagvalue]
      end

      def maybe_fallback(options={})
        fallback = GlobTagNode.new(to_glob(tagname), to_glob(tagvalue), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class GlobTagnameNode < GlobExpressionNode
      def initialize(tagname, separator=nil, options={})
        super(tagname.to_s, nil, separator, options)
      end

      def condition(options={})
        "LOWER(tags.name) GLOB LOWER(?)"
      end

      def condition_tables(options={})
        [:tags]
      end

      def condition_values(options={})
        [tagname]
      end

      def maybe_fallback(options={})
        fallback = GlobTagnameNode.new(to_glob(tagname), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class GlobTagvalueNode < GlobExpressionNode
      def initialize(tagvalue, separator=nil, options={})
        super(nil, tagvalue.to_s, separator, options)
      end

      def condition(options={})
        "LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?)"
      end

      def condition_tables(options={})
        [:hosts, :tags]
      end

      def condition_values(options={})
        [tagvalue, tagvalue]
      end

      def maybe_fallback(options={})
        fallback = GlobTagvalueNode.new(to_glob(tagvalue), separator)
        query = fallback.maybe_query(options)
        if query
          QueryExpressionNode.new(query, fallback.condition_values(options))
        else
          nil
        end
      end
    end

    class GlobHostOrTagNode < GlobExpressionNode
      def initialize(tagname, separator=nil, options={})
        super(tagname.to_s, nil, separator, options)
      end

      def condition(options={})
        "LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?)"
      end

      def condition_tables(options={})
        [:hosts, :tags]
      end

      def condition_values(options={})
        [tagname, tagname, tagname]
      end

      def maybe_fallback(options={})
        fallback = GlobHostOrTagNode.new(to_glob(tagname), separator)
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
        data[:tagname_regexp] = tagname.to_s if tagname
        data[:separator] = separator.to_s if separator
        data[:tagvalue_regexp] = tagvalue.to_s if tagvalue
        data[:fallback] = @options[:fallback].dump(options) if @options[:fallback]
        data
      end
    end

    class RegexpHostNode < RegexpExpressionNode
      def initialize(tagvalue, separator=nil, options={})
        case tagvalue
        when /\A\/(.*)\/\z/
          tagvalue = $1
        end
        super("@host", tagvalue, separator, options)
      end

      def condition(options={})
        "hosts.name REGEXP ?"
      end

      def condition_tables(options={})
        [:hosts]
      end

      def condition_values(options={})
        [tagvalue]
      end
    end

    class RegexpTagNode < RegexpExpressionNode
      def initialize(tagname, tagvalue, separator=nil, options={})
        case tagname
        when /\A\/(.*)\/\z/
          tagname = $1
        end
        case tagvalue
        when /\A\/(.*)\/\z/
          tagvalue = $1
        end
        super(tagname, tagvalue, separator, options)
      end

      def condition(options={})
        "tags.name REGEXP ? AND tags.value REGEXP ?"
      end

      def condition_tables(options={})
        [:tags]
      end

      def condition_values(options={})
        [tagname, tagvalue]
      end
    end

    class RegexpTagnameNode < RegexpExpressionNode
      def initialize(tagname, separator=nil, options={})
        case tagname
        when /\A\/(.*)\/\z/
          tagname = $1
        end
        super(tagname.to_s, nil, separator, options)
      end

      def condition(options={})
        "tags.name REGEXP ?"
      end

      def condition_tables(options={})
        [:tags]
      end

      def condition_values(options={})
        [tagname]
      end
    end

    class RegexpTagvalueNode < RegexpExpressionNode
      def initialize(tagvalue, separator=nil, options={})
        case tagvalue
        when /\A\/(.*)\/\z/
          tagvalue = $1
        end
        super(nil, tagvalue.to_s, separator, options)
      end

      def condition(options={})
        "hosts.name REGEXP ? OR tags.value REGEXP ?"
      end

      def condition_tables(options={})
        [:hosts, :tags]
      end

      def condition_values(options={})
        [tagvalue, tagvalue]
      end
    end

    class RegexpHostOrTagNode < RegexpExpressionNode
      def initialize(tagname, separator=nil, options={})
        super(tagname, nil, separator, options)
      end

      def condition(options={})
        "hosts.name REGEXP ? OR tags.name REGEXP ? OR tags.value REGEXP ?"
      end

      def condition_tables(options={})
        [:hosts, :tags]
      end

      def condition_values(options={})
        [tagname, tagname, tagname]
      end
    end
  end
end

# vim:set ft=ruby :
