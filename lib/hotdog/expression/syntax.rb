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
  end
end

# vim:set ft=ruby :
