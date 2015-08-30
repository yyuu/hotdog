require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "search" do
  let(:cmd) {
    Hotdog::Commands::Search.new(Hotdog::Application.new)
  }

  before(:each) do
    ENV["DATADOG_API_KEY"] = "DATADOG_API_KEY"
    ENV["DATADOG_APPLICATION_KEY"] = "DATADOG_APPLICATION_KEY"
  end

  it "parses ':foo'" do
    expect(cmd.parse(":foo")).to eq({attribute: "foo"})
  end

  it "parses ':foo*'" do
    expect(cmd.parse(":foo*")).to eq({attribute_glob: "foo*"})
  end

  it "parses ':/foo/'" do
    expect(cmd.parse(":/foo/")).to eq({attribute_regexp: "/foo/"})
  end

  it "parses 'foo'" do
    expect(cmd.parse("foo")).to eq({identifier: "foo"})
  end

  it "parses 'foo:bar'" do
    expect(cmd.parse("foo:bar")).to eq({identifier: "foo", attribute: "bar"})
  end

  it "parses 'foo: bar'" do
    expect(cmd.parse("foo:bar")).to eq({identifier: "foo", attribute: "bar"})
  end

  it "parses 'foo :bar'" do
    expect(cmd.parse("foo:bar")).to eq({identifier: "foo", attribute: "bar"})
  end

  it "parses 'foo : bar'" do
    expect(cmd.parse("foo:bar")).to eq({identifier: "foo", attribute: "bar"})
  end

  it "parses 'foo:bar*'" do
    expect(cmd.parse("foo:bar*")).to eq({identifier: "foo", attribute_glob: "bar*"})
  end

  it "parses 'foo*'" do
    expect(cmd.parse("foo*")).to eq({identifier_glob: "foo*"})
  end

  it "parses 'foo*:bar'" do
    expect(cmd.parse("foo*:bar")).to eq({identifier_glob: "foo*", attribute: "bar"})
  end

  it "parses 'foo*:bar*'" do
    expect(cmd.parse("foo*:bar*")).to eq({identifier_glob: "foo*", attribute_glob: "bar*"})
  end

  it "parses '/foo/'" do
    expect(cmd.parse("/foo/")).to eq({identifier_regexp: "/foo/"})
  end

  it "parses '/foo/:/bar/'" do
    expect(cmd.parse("/foo/:/bar/")).to eq({identifier_regexp: "/foo/", attribute_regexp: "/bar/"})
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
