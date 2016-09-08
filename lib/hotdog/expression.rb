#!/usr/bin/env ruby

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

require "hotdog/expression/semantics"
require "hotdog/expression/syntax"

module Hotdog
  module Expression
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
  end
end

# vim:set ft=ruby :
