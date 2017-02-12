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
      rule(tag_name_regexp: simple(:tag_name_regexp), separator: simple(:separator), tag_value_regexp: simple(:tag_value_regexp)) {
        if "/host/" == tag_name_regexp
          RegexpHostNode.new(tag_value_regexp, separator)
        else
          RegexpTagNode.new(tag_name_regexp, tag_value_regexp, separator)
        end
      }
      rule(tag_name_regexp: simple(:tag_name_regexp), separator: simple(:separator)) {
        if "/host/" == tag_name_regexp
          EverythingNode.new()
        else
          RegexpTagNameNode.new(tag_name_regexp, separator)
        end
      }
      rule(tag_name_regexp: simple(:tag_name_regexp)) {
        if "/host/" == tag_name_regexp
          EverythingNode.new()
        else
          RegexpHostOrTagNode.new(tag_name_regexp)
        end
      }
      rule(tag_name_glob: simple(:tag_name_glob), separator: simple(:separator), tag_value_glob: simple(:tag_value_glob)) {
        if "host" == tag_name_glob
          GlobHostNode.new(tag_value_glob, separator)
        else
          GlobTagNode.new(tag_name_glob, tag_value_glob, separator)
        end
      }
      rule(tag_name_glob: simple(:tag_name_glob), separator: simple(:separator), tag_value: simple(:tag_value)) {
        if "host" == tag_name_glob
          GlobHostNode.new(tag_value, separator)
        else
          GlobTagNode.new(tag_name_glob, tag_value, separator)
        end
      }
      rule(tag_name_glob: simple(:tag_name_glob), separator: simple(:separator)) {
        if "host" == tag_name_glob
          EverythingNode.new()
        else
          GlobTagNameNode.new(tag_name_glob, separator)
        end
      }
      rule(tag_name_glob: simple(:tag_name_glob)) {
        if "host" == tag_name_glob
          EverythingNode.new()
        else
          GlobHostOrTagNode.new(tag_name_glob)
        end
      }
      rule(tag_name: simple(:tag_name), separator: simple(:separator), tag_value_glob: simple(:tag_value_glob)) {
        if "host" == tag_name
          GlobHostNode.new(tag_value_glob, separator)
        else
          GlobTagNode.new(tag_name, tag_value_glob, separator)
        end
      }
      rule(tag_name: simple(:tag_name), separator: simple(:separator), tag_value: simple(:tag_value)) {
        if "host" == tag_name
          StringHostNode.new(tag_value, separator)
        else
          StringTagNode.new(tag_name, tag_value, separator)
        end
      }
      rule(tag_name: simple(:tag_name), separator: simple(:separator)) {
        if "host" == tag_name
          EverythingNode.new()
        else
          StringTagNameNode.new(tag_name, separator)
        end
      }
      rule(tag_name: simple(:tag_name)) {
        if "host" == tag_name
          EverythingNode.new()
        else
          StringHostOrTagNode.new(tag_name)
        end
      }
      rule(separator: simple(:separator), tag_value_regexp: simple(:tag_value_regexp)) {
        RegexpTagValueNode.new(tag_value_regexp, separator)
      }
      rule(tag_value_regexp: simple(:tag_value_regexp)) {
        RegexpTagValueNode.new(tag_value_regexp)
      }
      rule(separator: simple(:separator), tag_value_glob: simple(:tag_value_glob)) {
        GlobTagValueNode.new(tag_value_glob, separator)
      }
      rule(tag_value_glob: simple(:tag_value_glob)) {
        GlobTagValueNode.new(tag_value_glob)
      }
      rule(separator: simple(:separator), tag_value: simple(:tag_value)) {
        StringTagValueNode.new(tag_value, separator)
      }
      rule(tag_value: simple(:tag_value)) {
        StringTagValueNode.new(tag_value)
      }
    end
  end
end

# vim:set ft=ruby :
