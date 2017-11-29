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
      rule(tagname_regexp: simple(:tagname_regexp), separator: simple(:separator), tagvalue_regexp: simple(:tagvalue_regexp)) {
        if "/@host/" == tagname_regexp or "/host/" == tagname_regexp
          RegexpHostNode.new(tagvalue_regexp, separator)
        else
          RegexpTagNode.new(tagname_regexp, tagvalue_regexp, separator)
        end
      }
      rule(tagname_regexp: simple(:tagname_regexp), separator: simple(:separator)) {
        if "/@host/" == tagname_regexp or "/host/" == tagname_regexp
          EverythingNode.new()
        else
          RegexpTagnameNode.new(tagname_regexp, separator)
        end
      }
      rule(tagname_regexp: simple(:tagname_regexp)) {
        if "/@host/" == tagname_regexp or "/host/" == tagname_regexp
          EverythingNode.new()
        else
          RegexpHostOrTagNode.new(tagname_regexp)
        end
      }
      rule(tagname_glob: simple(:tagname_glob), separator: simple(:separator), tagvalue_glob: simple(:tagvalue_glob)) {
        if "@host" == tagname_glob or "host" == tagname_glob
          GlobHostNode.new(tagvalue_glob, separator)
        else
          GlobTagNode.new(tagname_glob, tagvalue_glob, separator)
        end
      }
      rule(tagname_glob: simple(:tagname_glob), separator: simple(:separator), tagvalue: simple(:tagvalue)) {
        if "@host" == tagname_glob or "host" == tagname_glob
          GlobHostNode.new(tagvalue, separator)
        else
          GlobTagNode.new(tagname_glob, tagvalue, separator)
        end
      }
      rule(tagname_glob: simple(:tagname_glob), separator: simple(:separator)) {
        if "@host" == tagname_glob or "host" == tagname_glob
          EverythingNode.new()
        else
          GlobTagnameNode.new(tagname_glob, separator)
        end
      }
      rule(tagname_glob: simple(:tagname_glob)) {
        if "@host" == tagname_glob or "host" == tagname_glob
          EverythingNode.new()
        else
          GlobHostOrTagNode.new(tagname_glob)
        end
      }
      rule(tagname: simple(:tagname), separator: simple(:separator), tagvalue_glob: simple(:tagvalue_glob)) {
        if "@host" == tagname or "host" == tagname
          GlobHostNode.new(tagvalue_glob, separator)
        else
          GlobTagNode.new(tagname, tagvalue_glob, separator)
        end
      }
      rule(tagname: simple(:tagname), separator: simple(:separator), tagvalue: simple(:tagvalue)) {
        if "@host" == tagname or "host" == tagname
          StringHostNode.new(tagvalue, separator)
        else
          StringTagNode.new(tagname, tagvalue, separator)
        end
      }
      rule(tagname: simple(:tagname), separator: simple(:separator)) {
        if "@host" == tagname or "host" == tagname
          EverythingNode.new()
        else
          StringTagnameNode.new(tagname, separator)
        end
      }
      rule(tagname: simple(:tagname)) {
        if "@host" == tagname or "host" == tagname
          EverythingNode.new()
        else
          StringHostOrTagNode.new(tagname)
        end
      }
      rule(separator: simple(:separator), tagvalue_regexp: simple(:tagvalue_regexp)) {
        RegexpTagvalueNode.new(tagvalue_regexp, separator)
      }
      rule(tagvalue_regexp: simple(:tagvalue_regexp)) {
        RegexpTagvalueNode.new(tagvalue_regexp)
      }
      rule(separator: simple(:separator), tagvalue_glob: simple(:tagvalue_glob)) {
        GlobTagvalueNode.new(tagvalue_glob, separator)
      }
      rule(tagvalue_glob: simple(:tagvalue_glob)) {
        GlobTagvalueNode.new(tagvalue_glob)
      }
      rule(separator: simple(:separator), tagvalue: simple(:tagvalue)) {
        StringTagvalueNode.new(tagvalue, separator)
      }
      rule(tagvalue: simple(:tagvalue)) {
        StringTagvalueNode.new(tagvalue)
      }
    end
  end
end

# vim:set ft=ruby :
