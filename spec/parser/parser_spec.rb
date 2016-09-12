require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "parser" do
  let(:cmd) {
    Hotdog::Commands::Search.new(Hotdog::Application.new)
  }

  before(:each) do
    ENV["DATADOG_API_KEY"] = "DATADOG_API_KEY"
    ENV["DATADOG_APPLICATION_KEY"] = "DATADOG_APPLICATION_KEY"
  end

  it "parses ':foo'" do
    expect(cmd.parse(":foo")).to eq({separator: ":", attribute: "foo"})
  end

  it "parses ':foo*'" do
    expect(cmd.parse(":foo*")).to eq({separator: ":", attribute_glob: "foo*"})
  end

  it "parses ':/foo/'" do
    expect(cmd.parse(":/foo/")).to eq({separator: ":", attribute_regexp: "/foo/"})
  end

  it "parses 'foo'" do
    expect(cmd.parse("foo")).to eq({identifier: "foo"})
  end

  it "parses 'foo:bar'" do
    expect(cmd.parse("foo:bar")).to eq({identifier: "foo", separator: ":", attribute: "bar"})
  end

  it "parses 'foo: bar'" do
    expect(cmd.parse("foo:bar")).to eq({identifier: "foo", separator: ":", attribute: "bar"})
  end

  it "parses 'foo :bar'" do
    expect(cmd.parse("foo:bar")).to eq({identifier: "foo", separator: ":", attribute: "bar"})
  end

  it "parses 'foo : bar'" do
    expect(cmd.parse("foo:bar")).to eq({identifier: "foo", separator: ":", attribute: "bar"})
  end

  it "parses 'foo:bar*'" do
    expect(cmd.parse("foo:bar*")).to eq({identifier: "foo", separator: ":", attribute_glob: "bar*"})
  end

  it "parses 'foo*'" do
    expect(cmd.parse("foo*")).to eq({identifier_glob: "foo*"})
  end

  it "parses 'foo*:bar'" do
    expect(cmd.parse("foo*:bar")).to eq({identifier_glob: "foo*", separator: ":", attribute: "bar"})
  end

  it "parses 'foo*:bar*'" do
    expect(cmd.parse("foo*:bar*")).to eq({identifier_glob: "foo*", separator: ":", attribute_glob: "bar*"})
  end

  it "parses '/foo/'" do
    expect(cmd.parse("/foo/")).to eq({identifier_regexp: "/foo/"})
  end

  it "parses '/foo/:/bar/'" do
    expect(cmd.parse("/foo/:/bar/")).to eq({identifier_regexp: "/foo/", separator: ":", attribute_regexp: "/bar/"})
  end

  it "parses '(foo)'" do
    expect(cmd.parse("(foo)")).to eq({identifier: "foo"})
  end

  it "parses '( foo )'" do
    expect(cmd.parse("( foo )")).to eq({identifier: "foo"})
  end

  it "parses ' ( foo ) '" do
    expect(cmd.parse(" ( foo ) ")).to eq({identifier: "foo"})
  end

  it "parses '((foo))'" do
    expect(cmd.parse("((foo))")).to eq({identifier: "foo"})
  end

  it "parses '(( foo ))'" do
    expect(cmd.parse("(( foo ))")).to eq({identifier: "foo"})
  end

  it "parses ' ( ( foo ) ) '" do
    expect(cmd.parse("( ( foo ) )")).to eq({identifier: "foo"})
  end

  it "parses 'identifier with prefix and'" do
    expect(cmd.parse("android")).to eq({identifier: "android"})
  end

  it "parses 'identifier with infix and'" do
    expect(cmd.parse("islander")).to eq({identifier: "islander"})
  end

  it "parses 'identifier with suffix and'" do
    expect(cmd.parse("mainland")).to eq({identifier: "mainland"})
  end

  it "parses 'identifier with prefix or'" do
    expect(cmd.parse("oreo")).to eq({identifier: "oreo"})
  end

  it "parses 'identifier with infix or'" do
    expect(cmd.parse("category")).to eq({identifier: "category"})
  end

  it "parses 'identifier with suffix or'" do
    expect(cmd.parse("imperator")).to eq({identifier: "imperator"})
  end

  it "parses 'identifier with prefix not'" do
    expect(cmd.parse("nothing")).to eq({identifier: "nothing"})
  end

  it "parses 'identifier with infix not'" do
    expect(cmd.parse("annotation")).to eq({identifier: "annotation"})
  end

  it "parses 'identifier with suffix not'" do
    expect(cmd.parse("forgetmenot")).to eq({identifier: "forgetmenot"})
  end

  it "parses 'foo bar'" do
    expect(cmd.parse("foo bar")).to eq({left: {identifier: "foo"}, binary_op: nil, right: {identifier: "bar"}})
  end

  it "parses 'foo bar baz'" do
    expect(cmd.parse("foo bar baz")).to eq({left: {identifier: "foo"}, binary_op: nil, right: {left: {identifier: "bar"}, binary_op: nil, right: {identifier: "baz"}}})
  end

  it "parses 'not foo'" do
    expect(cmd.parse("not foo")).to eq({unary_op: "not", expression: {identifier: "foo"}})
  end

  it "parses '! foo'" do
    expect(cmd.parse("! foo")).to eq({unary_op: "!", expression: {identifier: "foo"}})
  end

  it "parses '~ foo'" do
    expect(cmd.parse("~ foo")).to eq({unary_op: "~", expression: {identifier: "foo"}})
  end

  it "parses 'not(not foo)'" do
    expect(cmd.parse("not(not foo)")).to eq({unary_op: "not", expression: {unary_op: "not", expression: {identifier: "foo"}}})
  end

  it "parses '!(!foo)'" do
    expect(cmd.parse("!(!foo)")).to eq({unary_op: "!", expression: {unary_op: "!", expression: {identifier: "foo"}}})
  end

  it "parses '~(~foo)'" do
    expect(cmd.parse("~(~foo)")).to eq({unary_op: "~", expression: {unary_op: "~", expression: {identifier: "foo"}}})
  end

  it "parses 'not not foo'" do
    expect(cmd.parse("not not foo")).to eq({unary_op: "not", expression: {unary_op: "not", expression: {identifier: "foo"}}})
  end

  it "parses '!!foo'" do
    expect(cmd.parse("!! foo")).to eq({unary_op: "!", expression: {unary_op: "!", expression: {identifier: "foo"}}})
  end

  it "parses '! ! foo'" do
    expect(cmd.parse("!! foo")).to eq({unary_op: "!", expression: {unary_op: "!", expression: {identifier: "foo"}}})
  end

  it "parses '~~foo'" do
    expect(cmd.parse("~~ foo")).to eq({unary_op: "~", expression: {unary_op: "~", expression: {identifier: "foo"}}})
  end

  it "parses '~ ~ foo'" do
    expect(cmd.parse("~~ foo")).to eq({unary_op: "~", expression: {unary_op: "~", expression: {identifier: "foo"}}})
  end

  it "parses 'foo and bar'" do
    expect(cmd.parse("foo and bar")).to eq({left: {identifier: "foo"}, binary_op: "and", right: {identifier: "bar"}})
  end

  it "parses 'foo and bar and baz'" do
    expect(cmd.parse("foo and bar and baz")).to eq({left: {identifier: "foo"}, binary_op: "and", right: {left: {identifier: "bar"}, binary_op: "and", right: {identifier: "baz"}}})
  end

  it "parses 'foo&bar'" do
    expect(cmd.parse("foo&bar")).to eq({left: {identifier: "foo"}, binary_op: "&", right: {identifier: "bar"}})
  end

  it "parses 'foo & bar'" do
    expect(cmd.parse("foo & bar")).to eq({left: {identifier: "foo"}, binary_op: "&", right: {identifier: "bar"}})
  end

  it "parses 'foo&bar&baz'" do
    expect(cmd.parse("foo & bar & baz")).to eq({left: {identifier: "foo"}, binary_op: "&", right: {left: {identifier: "bar"}, binary_op: "&", right: {identifier: "baz"}}})
  end

  it "parses 'foo & bar & baz'" do
    expect(cmd.parse("foo & bar & baz")).to eq({left: {identifier: "foo"}, binary_op: "&", right: {left: {identifier: "bar"}, binary_op: "&", right: {identifier: "baz"}}})
  end

  it "parses 'foo&&bar'" do
    expect(cmd.parse("foo&&bar")).to eq({left: {identifier: "foo"}, binary_op: "&&", right: {identifier: "bar"}})
  end

  it "parses 'foo && bar'" do
    expect(cmd.parse("foo && bar")).to eq({left: {identifier: "foo"}, binary_op: "&&", right: {identifier: "bar"}})
  end

  it "parses 'foo&&bar&&baz'" do
    expect(cmd.parse("foo&&bar&&baz")).to eq({left: {identifier: "foo"}, binary_op: "&&", right: {left: {identifier: "bar"}, binary_op: "&&", right: {identifier: "baz"}}})
  end

  it "parses 'foo && bar && baz'" do
    expect(cmd.parse("foo && bar && baz")).to eq({left: {identifier: "foo"}, binary_op: "&&", right: {left: {identifier: "bar"}, binary_op: "&&", right: {identifier: "baz"}}})
  end

  it "parses 'foo or bar'" do
    expect(cmd.parse("foo or bar")).to eq({left: {identifier: "foo"}, binary_op: "or", right: {identifier: "bar"}})
  end

  it "parses 'foo or bar or baz'" do
    expect(cmd.parse("foo or bar or baz")).to eq({left: {identifier: "foo"}, binary_op: "or", right: {left: {identifier: "bar"}, binary_op: "or", right: {identifier: "baz"}}})
  end

  it "parses 'foo|bar'" do
    expect(cmd.parse("foo|bar")).to eq({left: {identifier: "foo"}, binary_op: "|", right: {identifier: "bar"}})
  end

  it "parses 'foo | bar'" do
    expect(cmd.parse("foo | bar")).to eq({left: {identifier: "foo"}, binary_op: "|", right: {identifier: "bar"}})
  end

  it "parses 'foo|bar|baz'" do
    expect(cmd.parse("foo|bar|baz")).to eq({left: {identifier: "foo"}, binary_op: "|", right: {left: {identifier: "bar"}, binary_op: "|", right: {identifier: "baz"}}})
  end

  it "parses 'foo | bar | baz'" do
    expect(cmd.parse("foo | bar | baz")).to eq({left: {identifier: "foo"}, binary_op: "|", right: {left: {identifier: "bar"}, binary_op: "|", right: {identifier: "baz"}}})
  end

  it "parses 'foo||bar'" do
    expect(cmd.parse("foo||bar")).to eq({left: {identifier: "foo"}, binary_op: "||", right: {identifier: "bar"}})
  end

  it "parses 'foo || bar'" do
    expect(cmd.parse("foo || bar")).to eq({left: {identifier: "foo"}, binary_op: "||", right: {identifier: "bar"}})
  end

  it "parses 'foo||bar||baz'" do
    expect(cmd.parse("foo||bar||baz")).to eq({left: {identifier: "foo"}, binary_op: "||", right: {left: {identifier: "bar"}, binary_op: "||", right: {identifier: "baz"}}})
  end

  it "parses 'foo || bar || baz'" do
    expect(cmd.parse("foo || bar || baz")).to eq({left: {identifier: "foo"}, binary_op: "||", right: {left: {identifier: "bar"}, binary_op: "||", right: {identifier: "baz"}}})
  end

  it "parses '(foo and bar) or baz'" do
    expect(cmd.parse("(foo and bar) or baz")).to eq({left: {left: {identifier: "foo"}, binary_op: "and", right: {identifier: "bar"}}, binary_op: "or", right: {identifier: "baz"}})
  end

  it "parses 'foo and (bar or baz)'" do
    expect(cmd.parse("foo and (bar or baz)")).to eq({left: {identifier: "foo"}, binary_op: "and", right: {left: {identifier: "bar"}, binary_op: "or", right: {identifier: "baz"}}})
  end

  it "parses 'not foo and bar'" do
    expect(cmd.parse("not foo and bar")).to eq({unary_op: "not", expression: {left: {identifier: "foo"}, binary_op: "and", right: {identifier: "bar"}}})
  end

  it "parses '! foo and bar'" do
    expect(cmd.parse("! foo and bar")).to eq({left: {unary_op: "!", expression: {identifier: "foo"}}, binary_op: "and", right: {identifier: "bar"}})
  end

  it "parses 'not foo && bar'" do
    expect(cmd.parse("not foo && bar")).to eq({unary_op: "not", expression: {left: {identifier: "foo"}, binary_op: "&&", right: {identifier: "bar"}}})
  end

  it "parses '! foo && bar'" do
    expect(cmd.parse("! foo && bar")).to eq({left: {unary_op: "!", expression: {identifier: "foo"}}, binary_op: "&&", right: {identifier: "bar"}})
  end

  it "is unable to parse ' '" do
    expect {
      cmd.parse(" ")
    }.to raise_error(Parslet::ParseFailed)
  end

  it "is unable to parse '((()))'" do
    expect {
      cmd.parse("((()))")
    }.to raise_error(Parslet::ParseFailed)
  end

  it "is unable to parse 'foo and'" do
    expect {
      cmd.parse("foo and")
    }.to raise_error(Parslet::ParseFailed)
  end

  it "is unable to parse 'foo &'" do
    expect {
      cmd.parse("foo &")
    }.to raise_error(Parslet::ParseFailed)
  end

  it "is unable to parse 'foo &&'" do
    expect {
      cmd.parse("foo &&")
    }.to raise_error(Parslet::ParseFailed)
  end

  it "is unable to parse 'and foo'" do
    expect {
      cmd.parse("and foo")
    }.to raise_error(Parslet::ParseFailed)
  end

  it "is unable to parse '& foo'" do
    expect {
      cmd.parse("& foo")
    }.to raise_error(Parslet::ParseFailed)
  end

  it "is unable to parse '&& foo'" do
    expect {
      cmd.parse("&& foo")
    }.to raise_error(Parslet::ParseFailed)
  end
end
