#!/usr/bin/env ruby

require "parslet"

module Hotdog
  module Expression
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
        ( str('!').as(:unary_op) >> spacing.maybe >> primary.as(:expression) >> spacing.maybe \
        | str('~').as(:unary_op) >> spacing.maybe >> primary.as(:expression) >> spacing.maybe \
        | str('!').as(:unary_op) >> spacing.maybe >> expression.as(:expression) \
        | str('~').as(:unary_op) >> spacing.maybe >> expression.as(:expression) \
        | spacing.maybe >> primary >> spacing.maybe \
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
      rule(:funcall) {
        ( funcall_identifier.as(:funcall) >> spacing.maybe >> str('(') >> spacing.maybe >> str(')') \
        | funcall_identifier.as(:funcall) >> spacing.maybe >> str('(') >> spacing.maybe >> funcall_args.as(:funcall_args) >> spacing.maybe >> str(')') \
        )
      }
      rule(:funcall_identifier) {
        ( binary_op.absent? >> unary_op.absent? >> match('[A-Z_a-z]') >> match('[0-9A-Z_a-z]').repeat(0) \
        | binary_op >> match('[0-9A-Z_a-z]').repeat(1) \
        | unary_op >> match('[0-9A-Z_a-z]').repeat(1) \
        )
      }
      rule(:funcall_args) {
        ( funcall_arg.as(:funcall_args_head) >> spacing.maybe >> str(',') >> spacing.maybe >> funcall_args.as(:funcall_args_tail) \
        | funcall_arg.as(:funcall_args_head) \
        )
      }
      rule(:funcall_arg) {
        ( float.as(:float) \
        | integer.as(:integer) \
        | string.as(:string) \
        | regexp.as(:regexp) \
        | primary \
        )
      }
      rule(:float) {
        ( match('[0-9]').repeat(1) >> str('.') >> match('[0-9]').repeat(1) \
        )
      }
      rule(:integer) {
        ( match('[1-9]').repeat(1) >> match('[0-9]').repeat(0) \
        )
      }
      rule(:string) {
        ( str('"') >> (str('"').absent? >> any).repeat(0) >> str('"') \
        | str("'") >> (str("'").absent? >> any).repeat(0) >> str("'") \
        )
      }
      rule(:regexp) {
        ( str('/') >> (str('/').absent? >> any).repeat(0) >> str('/') \
        )
      }
      rule(:primary) {
        ( str('(') >> expression >> str(')') \
        | funcall \
        | tag \
        )
      }
      rule(:tag) {
        ( regexp.as(:tag_name_regexp) >> separator.as(:separator) >> regexp.as(:tag_value_regexp) \
        | regexp.as(:tag_name_regexp) >> separator.as(:separator) \
        | regexp.as(:tag_name_regexp) \
        | tag_name_glob.as(:tag_name_glob) >> separator.as(:separator) >> tag_value_glob.as(:tag_value_glob) \
        | tag_name_glob.as(:tag_name_glob) >> separator.as(:separator) >> tag_value.as(:tag_value) \
        | tag_name_glob.as(:tag_name_glob) >> separator.as(:separator) \
        | tag_name_glob.as(:tag_name_glob) \
        | tag_name.as(:tag_name) >> separator.as(:separator) >> tag_value_glob.as(:tag_value_glob) \
        | tag_name.as(:tag_name) >> separator.as(:separator) >> tag_value.as(:tag_value) \
        | tag_name.as(:tag_name) >> separator.as(:separator) \
        | tag_name.as(:tag_name) \
        | separator.as(:separator) >> regexp.as(:tag_value_regexp) \
        | separator.as(:separator) >> tag_value_glob.as(:tag_value_glob) \
        | separator.as(:separator) >> tag_value.as(:tag_value) \
        | tag_value_regexp.as(:tag_value_regexp) \
        | tag_value_glob.as(:tag_value_glob) \
        | tag_value.as(:tag_value) \
        )
      }
      rule(:tag_name_regexp) {
        ( regexp \
        )
      }
      rule(:tag_value_regexp) {
        ( regexp \
        )
      }
      rule(:tag_name_glob) {
        ( binary_op.absent? >> unary_op.absent? >> tag_name.repeat(0) >> (glob_char >> tag_name.maybe).repeat(1) \
        | binary_op >> (glob_char >> tag_name.maybe).repeat(1) \
        | unary_op >> (glob_char >> tag_name.maybe).repeat(1) \
        )
      }
      rule(:tag_value_glob) {
        ( binary_op.absent? >> unary_op.absent? >> tag_value.repeat(0) >> (glob_char >> tag_value.maybe).repeat(1) \
        | binary_op >> (glob_char >> tag_value.maybe).repeat(1) \
        | unary_op >> (glob_char >> tag_value.maybe).repeat(1) \
        )
      }
      rule(:tag_name) {
        ( binary_op.absent? >> unary_op.absent? >> match('[A-Z_a-z]') >> match('[-./0-9A-Z_a-z]').repeat(0) \
        | binary_op >> match('[-./0-9A-Z_a-z]').repeat(1) \
        | unary_op >> match('[-./0-9A-Z_a-z]').repeat(1) \
        )
      }
      rule(:tag_value) {
        ( binary_op.absent? >> unary_op.absent? >> match('[-./0-9:A-Z_a-z]').repeat(1) \
        | binary_op >> match('[-./0-9:A-Z_a-z]').repeat(1) \
        | unary_op >> match('[-./0-9:A-Z_a-z]').repeat(1) \
        )
      }
      rule(:separator) {
        ( str(':') \
        | str('=') \
        )
      }
      rule(:glob_char) {
        ( str('*') | str('?') | str('[') | str(']') )
      }
      rule(:spacing) {
        ( match('[\t\n\r ]').repeat(1) \
        )
      }
    end
  end
end

# vim:set ft=ruby :
