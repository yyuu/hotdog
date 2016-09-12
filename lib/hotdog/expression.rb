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
      rule(float: simple(:float)) {
        float.to_f
      }
      rule(integer: simple(:integer)) {
        integer.to_i
      }
      rule(string: simple(:string)) {
        case string
        when /\A"(.*)"\z/
          $1
        when /\A'(.*)'\z/
          $1
        else
          string
        end
      }
      rule(regexp: simple(:regexp)) {
        case regexp
        when /\A\/(.*)\/\z/
          $1
        else
          regexp
        end
      }
      rule(funcall_args_head: simple(:funcall_args_head), funcall_args_tail: sequence(:funcall_args_tail)) {
        [funcall_args_head] + funcall_args_tail
      }
      rule(funcall_args_head: simple(:funcall_args_head)) {
        [funcall_args_head]
      }
      rule(funcall: simple(:funcall), funcall_args: sequence(:funcall_args)) {
        FuncallNode.new(funcall, funcall_args)
      }
      rule(funcall: simple(:funcall)) {
        FuncallNode.new(funcall, [])
      }
      rule(binary_op: simple(:binary_op), left: simple(:left), right: simple(:right)) {
        BinaryExpressionNode.new(binary_op, left, right)
      }
      rule(unary_op: simple(:unary_op), expression: simple(:expression)) {
        UnaryExpressionNode.new(unary_op, expression)
      }
      rule(identifier_regexp: simple(:identifier_regexp), separator: simple(:separator), attribute_regexp: simple(:attribute_regexp)) {
        if "/host/" == identifier_regexp
          RegexpHostNode.new(attribute_regexp, separator)
        else
          RegexpTagNode.new(identifier_regexp, attribute_regexp, separator)
        end
      }
      rule(identifier_regexp: simple(:identifier_regexp), separator: simple(:separator)) {
        if "/host/" == identifier_regexp
          EverythingNode.new()
        else
          RegexpTagNameNode.new(identifier_regexp, separator)
        end
      }
      rule(identifier_regexp: simple(:identifier_regexp)) {
        if "/host/" == identifier_regexp
          EverythingNode.new()
        else
          RegexpNode.new(identifier_regexp)
        end
      }
      rule(identifier_glob: simple(:identifier_glob), separator: simple(:separator), attribute_glob: simple(:attribute_glob)) {
        if "host" == identifier_glob
          GlobHostNode.new(attribute_glob, separator)
        else
          GlobTagNode.new(identifier_glob, attribute_glob, separator)
        end
      }
      rule(identifier_glob: simple(:identifier_glob), separator: simple(:separator), attribute: simple(:attribute)) {
        if "host" == identifier_glob
          GlobHostNode.new(attribute, separator)
        else
          GlobTagNode.new(identifier, attribute, separator)
        end
      }
      rule(identifier_glob: simple(:identifier_glob), separator: simple(:separator)) {
        if "host" == identifier_glob
          EverythingNode.new()
        else
          GlobTagNameNode.new(identifier_glob, separator)
        end
      }
      rule(identifier_glob: simple(:identifier_glob)) {
        if "host" == identifier_glob
          EverythingNode.new()
        else
          GlobNode.new(identifier_glob)
        end
      }
      rule(identifier: simple(:identifier), separator: simple(:separator), attribute_glob: simple(:attribute_glob)) {
        if "host" == identifier
          GlobHostNode.new(attribute_glob, separator)
        else
          GlobTagNode.new(identifier, attribute_glob, separator)
        end
      }
      rule(identifier: simple(:identifier), separator: simple(:separator), attribute: simple(:attribute)) {
        if "host" == identifier
          StringHostNode.new(attribute, separator)
        else
          StringTagNode.new(identifier, attribute, separator)
        end
      }
      rule(identifier: simple(:identifier), separator: simple(:separator)) {
        if "host" == identifier
          EverythingNode.new()
        else
          StringTagNameNode.new(identifier, separator)
        end
      }
      rule(identifier: simple(:identifier)) {
        if "host" == identifier
          EverythingNode.new()
        else
          StringNode.new(identifier)
        end
      }
      rule(separator: simple(:separator), attribute_regexp: simple(:attribute_regexp)) {
        RegexpTagValueNode.new(attribute_regexp, separator)
      }
      rule(attribute_regexp: simple(:attribute_regexp)) {
        RegexpTagValueNode.new(attribute_regexp)
      }
      rule(separator: simple(:separator), attribute_glob: simple(:attribute_glob)) {
        GlobTagValueNode.new(attribute_glob, separator)
      }
      rule(attribute_glob: simple(:attribute_glob)) {
        GlobTagValueNode.new(attribute_glob)
      }
      rule(separator: simple(:separator), attribute: simple(:attribute)) {
        StringTagValueNode.new(attribute, separator)
      }
      rule(attribute: simple(:attribute)) {
        StringTagValueNode.new(attribute)
      }
    end
  end
end

# vim:set ft=ruby :
