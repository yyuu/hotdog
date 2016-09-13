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
    expect(cmd.parse(":foo")).to eq({separator: ":", tag_value: "foo"})
  end

  it "parses ':foo*'" do
    expect(cmd.parse(":foo*")).to eq({separator: ":", tag_value_glob: "foo*"})
  end

  it "parses ':/foo/'" do
    expect(cmd.parse(":/foo/")).to eq({separator: ":", tag_value_regexp: "/foo/"})
  end

  it "parses 'foo'" do
    expect(cmd.parse("foo")).to eq({tag_name: "foo"})
  end

  it "parses 'foo:bar'" do
    expect(cmd.parse("foo:bar")).to eq({tag_name: "foo", separator: ":", tag_value: "bar"})
  end

  it "parses 'foo: bar'" do
    expect(cmd.parse("foo:bar")).to eq({tag_name: "foo", separator: ":", tag_value: "bar"})
  end

  it "parses 'foo :bar'" do
    expect(cmd.parse("foo:bar")).to eq({tag_name: "foo", separator: ":", tag_value: "bar"})
  end

  it "parses 'foo : bar'" do
    expect(cmd.parse("foo:bar")).to eq({tag_name: "foo", separator: ":", tag_value: "bar"})
  end

  it "parses 'foo:bar*'" do
    expect(cmd.parse("foo:bar*")).to eq({tag_name: "foo", separator: ":", tag_value_glob: "bar*"})
  end

  it "parses 'foo*'" do
    expect(cmd.parse("foo*")).to eq({tag_name_glob: "foo*"})
  end

  it "parses 'foo*:bar'" do
    expect(cmd.parse("foo*:bar")).to eq({tag_name_glob: "foo*", separator: ":", tag_value: "bar"})
  end

  it "parses 'foo*:bar*'" do
    expect(cmd.parse("foo*:bar*")).to eq({tag_name_glob: "foo*", separator: ":", tag_value_glob: "bar*"})
  end

  it "parses '/foo/'" do
    expect(cmd.parse("/foo/")).to eq({tag_name_regexp: "/foo/"})
  end

  it "parses '/foo/:/bar/'" do
    expect(cmd.parse("/foo/:/bar/")).to eq({tag_name_regexp: "/foo/", separator: ":", tag_value_regexp: "/bar/"})
  end

  it "parses '(foo)'" do
    expect(cmd.parse("(foo)")).to eq({tag_name: "foo"})
  end

  it "parses '( foo )'" do
    expect(cmd.parse("( foo )")).to eq({tag_name: "foo"})
  end

  it "parses ' ( foo ) '" do
    expect(cmd.parse(" ( foo ) ")).to eq({tag_name: "foo"})
  end

  it "parses '((foo))'" do
    expect(cmd.parse("((foo))")).to eq({tag_name: "foo"})
  end

  it "parses '(( foo ))'" do
    expect(cmd.parse("(( foo ))")).to eq({tag_name: "foo"})
  end

  it "parses ' ( ( foo ) ) '" do
    expect(cmd.parse("( ( foo ) )")).to eq({tag_name: "foo"})
  end

  it "parses 'tag_name with prefix and'" do
    expect(cmd.parse("android")).to eq({tag_name: "android"})
  end

  it "parses 'tag_name with infix and'" do
    expect(cmd.parse("islander")).to eq({tag_name: "islander"})
  end

  it "parses 'tag_name with suffix and'" do
    expect(cmd.parse("mainland")).to eq({tag_name: "mainland"})
  end

  it "parses 'tag_name with prefix or'" do
    expect(cmd.parse("oreo")).to eq({tag_name: "oreo"})
  end

  it "parses 'tag_name with infix or'" do
    expect(cmd.parse("category")).to eq({tag_name: "category"})
  end

  it "parses 'tag_name with suffix or'" do
    expect(cmd.parse("imperator")).to eq({tag_name: "imperator"})
  end

  it "parses 'tag_name with prefix not'" do
    expect(cmd.parse("nothing")).to eq({tag_name: "nothing"})
  end

  it "parses 'tag_name with infix not'" do
    expect(cmd.parse("annotation")).to eq({tag_name: "annotation"})
  end

  it "parses 'tag_name with suffix not'" do
    expect(cmd.parse("forgetmenot")).to eq({tag_name: "forgetmenot"})
  end

  it "parses 'foo bar'" do
    expect(cmd.parse("foo bar")).to eq({left: {tag_name: "foo"}, binary_op: nil, right: {tag_name: "bar"}})
  end

  it "parses 'foo bar baz'" do
    expect(cmd.parse("foo bar baz")).to eq({left: {tag_name: "foo"}, binary_op: nil, right: {left: {tag_name: "bar"}, binary_op: nil, right: {tag_name: "baz"}}})
  end

  it "parses 'not foo'" do
    expect(cmd.parse("not foo")).to eq({unary_op: "not", expression: {tag_name: "foo"}})
  end

  it "parses '! foo'" do
    expect(cmd.parse("! foo")).to eq({unary_op: "!", expression: {tag_name: "foo"}})
  end

  it "parses '~ foo'" do
    expect(cmd.parse("~ foo")).to eq({unary_op: "~", expression: {tag_name: "foo"}})
  end

  it "parses 'not(not foo)'" do
    expect(cmd.parse("not(not foo)")).to eq({unary_op: "not", expression: {unary_op: "not", expression: {tag_name: "foo"}}})
  end

  it "parses '!(!foo)'" do
    expect(cmd.parse("!(!foo)")).to eq({unary_op: "!", expression: {unary_op: "!", expression: {tag_name: "foo"}}})
  end

  it "parses '~(~foo)'" do
    expect(cmd.parse("~(~foo)")).to eq({unary_op: "~", expression: {unary_op: "~", expression: {tag_name: "foo"}}})
  end

  it "parses 'not not foo'" do
    expect(cmd.parse("not not foo")).to eq({unary_op: "not", expression: {unary_op: "not", expression: {tag_name: "foo"}}})
  end

  it "parses '!!foo'" do
    expect(cmd.parse("!! foo")).to eq({unary_op: "!", expression: {unary_op: "!", expression: {tag_name: "foo"}}})
  end

  it "parses '! ! foo'" do
    expect(cmd.parse("!! foo")).to eq({unary_op: "!", expression: {unary_op: "!", expression: {tag_name: "foo"}}})
  end

  it "parses '~~foo'" do
    expect(cmd.parse("~~ foo")).to eq({unary_op: "~", expression: {unary_op: "~", expression: {tag_name: "foo"}}})
  end

  it "parses '~ ~ foo'" do
    expect(cmd.parse("~~ foo")).to eq({unary_op: "~", expression: {unary_op: "~", expression: {tag_name: "foo"}}})
  end

  it "parses 'foo and bar'" do
    expect(cmd.parse("foo and bar")).to eq({left: {tag_name: "foo"}, binary_op: "and", right: {tag_name: "bar"}})
  end

  it "parses 'foo and bar and baz'" do
    expect(cmd.parse("foo and bar and baz")).to eq({left: {tag_name: "foo"}, binary_op: "and", right: {left: {tag_name: "bar"}, binary_op: "and", right: {tag_name: "baz"}}})
  end

  it "parses 'foo&bar'" do
    expect(cmd.parse("foo&bar")).to eq({left: {tag_name: "foo"}, binary_op: "&", right: {tag_name: "bar"}})
  end

  it "parses 'foo & bar'" do
    expect(cmd.parse("foo & bar")).to eq({left: {tag_name: "foo"}, binary_op: "&", right: {tag_name: "bar"}})
  end

  it "parses 'foo&bar&baz'" do
    expect(cmd.parse("foo & bar & baz")).to eq({left: {tag_name: "foo"}, binary_op: "&", right: {left: {tag_name: "bar"}, binary_op: "&", right: {tag_name: "baz"}}})
  end

  it "parses 'foo & bar & baz'" do
    expect(cmd.parse("foo & bar & baz")).to eq({left: {tag_name: "foo"}, binary_op: "&", right: {left: {tag_name: "bar"}, binary_op: "&", right: {tag_name: "baz"}}})
  end

  it "parses 'foo&&bar'" do
    expect(cmd.parse("foo&&bar")).to eq({left: {tag_name: "foo"}, binary_op: "&&", right: {tag_name: "bar"}})
  end

  it "parses 'foo && bar'" do
    expect(cmd.parse("foo && bar")).to eq({left: {tag_name: "foo"}, binary_op: "&&", right: {tag_name: "bar"}})
  end

  it "parses 'foo&&bar&&baz'" do
    expect(cmd.parse("foo&&bar&&baz")).to eq({left: {tag_name: "foo"}, binary_op: "&&", right: {left: {tag_name: "bar"}, binary_op: "&&", right: {tag_name: "baz"}}})
  end

  it "parses 'foo && bar && baz'" do
    expect(cmd.parse("foo && bar && baz")).to eq({left: {tag_name: "foo"}, binary_op: "&&", right: {left: {tag_name: "bar"}, binary_op: "&&", right: {tag_name: "baz"}}})
  end

  it "parses 'foo or bar'" do
    expect(cmd.parse("foo or bar")).to eq({left: {tag_name: "foo"}, binary_op: "or", right: {tag_name: "bar"}})
  end

  it "parses 'foo or bar or baz'" do
    expect(cmd.parse("foo or bar or baz")).to eq({left: {tag_name: "foo"}, binary_op: "or", right: {left: {tag_name: "bar"}, binary_op: "or", right: {tag_name: "baz"}}})
  end

  it "parses 'foo|bar'" do
    expect(cmd.parse("foo|bar")).to eq({left: {tag_name: "foo"}, binary_op: "|", right: {tag_name: "bar"}})
  end

  it "parses 'foo | bar'" do
    expect(cmd.parse("foo | bar")).to eq({left: {tag_name: "foo"}, binary_op: "|", right: {tag_name: "bar"}})
  end

  it "parses 'foo|bar|baz'" do
    expect(cmd.parse("foo|bar|baz")).to eq({left: {tag_name: "foo"}, binary_op: "|", right: {left: {tag_name: "bar"}, binary_op: "|", right: {tag_name: "baz"}}})
  end

  it "parses 'foo | bar | baz'" do
    expect(cmd.parse("foo | bar | baz")).to eq({left: {tag_name: "foo"}, binary_op: "|", right: {left: {tag_name: "bar"}, binary_op: "|", right: {tag_name: "baz"}}})
  end

  it "parses 'foo||bar'" do
    expect(cmd.parse("foo||bar")).to eq({left: {tag_name: "foo"}, binary_op: "||", right: {tag_name: "bar"}})
  end

  it "parses 'foo || bar'" do
    expect(cmd.parse("foo || bar")).to eq({left: {tag_name: "foo"}, binary_op: "||", right: {tag_name: "bar"}})
  end

  it "parses 'foo||bar||baz'" do
    expect(cmd.parse("foo||bar||baz")).to eq({left: {tag_name: "foo"}, binary_op: "||", right: {left: {tag_name: "bar"}, binary_op: "||", right: {tag_name: "baz"}}})
  end

  it "parses 'foo || bar || baz'" do
    expect(cmd.parse("foo || bar || baz")).to eq({left: {tag_name: "foo"}, binary_op: "||", right: {left: {tag_name: "bar"}, binary_op: "||", right: {tag_name: "baz"}}})
  end

  it "parses '(foo and bar) or baz'" do
    expect(cmd.parse("(foo and bar) or baz")).to eq({left: {left: {tag_name: "foo"}, binary_op: "and", right: {tag_name: "bar"}}, binary_op: "or", right: {tag_name: "baz"}})
  end

  it "parses 'foo and (bar or baz)'" do
    expect(cmd.parse("foo and (bar or baz)")).to eq({left: {tag_name: "foo"}, binary_op: "and", right: {left: {tag_name: "bar"}, binary_op: "or", right: {tag_name: "baz"}}})
  end

  it "parses 'not foo and bar'" do
    expect(cmd.parse("not foo and bar")).to eq({unary_op: "not", expression: {left: {tag_name: "foo"}, binary_op: "and", right: {tag_name: "bar"}}})
  end

  it "parses '! foo and bar'" do
    expect(cmd.parse("! foo and bar")).to eq({left: {unary_op: "!", expression: {tag_name: "foo"}}, binary_op: "and", right: {tag_name: "bar"}})
  end

  it "parses 'not foo && bar'" do
    expect(cmd.parse("not foo && bar")).to eq({unary_op: "not", expression: {left: {tag_name: "foo"}, binary_op: "&&", right: {tag_name: "bar"}}})
  end

  it "parses '! foo && bar'" do
    expect(cmd.parse("! foo && bar")).to eq({left: {unary_op: "!", expression: {tag_name: "foo"}}, binary_op: "&&", right: {tag_name: "bar"}})
  end

  it "parses 'f(x)'" do
    expect(cmd.parse("f(x)")).to eq({funcall: "f", funcall_args: {funcall_args_head: {tag_name: "x"}}})
  end

  it "parses 'f(x, \"y\")'" do
    expect(cmd.parse("f(x, \"y\")")).to eq({funcall: "f", funcall_args: {funcall_args_head: {tag_name: "x"}, funcall_args_tail: {funcall_args_head: {string: "\"y\""}}}})
  end

  it "parses 'f(x, \"y\", /z/)'" do
    expect(cmd.parse("f(x, \"y\", /z/)")).to eq({funcall: "f", funcall_args: {funcall_args_head: {tag_name: "x"}, funcall_args_tail: {funcall_args_head: {string: "\"y\""}, funcall_args_tail: {funcall_args_head: {regexp: "/z/"}}}}})
  end

  it "parses 'g ( 12345 )'" do
    expect(cmd.parse("g ( 12345 )")).to eq({funcall: "g", funcall_args: {funcall_args_head: {integer: "12345"}}})
  end

  it "parses 'g ( 12345 , 3.1415 )'" do
    expect(cmd.parse("g ( 12345 , 3.1415 )")).to eq({funcall: "g", funcall_args: {funcall_args_head: {integer: "12345"}, funcall_args_tail: {funcall_args_head: {float: "3.1415"}}}})
  end

  it "parses 'f()'" do
    expect(cmd.parse("f()")).to eq({funcall: "f"})
  end

  it "parses 'g(f())'" do
    expect(cmd.parse("g(f())")).to eq({funcall: "g", funcall_args: {funcall_args_head: {funcall: "f"}}})
  end

  it "parses 'foo and bar(y)'" do
    expect(cmd.parse("foo and bar(y)")).to eq({binary_op: "and", left: {tag_name: "foo"}, right: {funcall: "bar", funcall_args: {funcall_args_head: {tag_name: "y"}}}})
  end

  it "parses 'foo(x) and bar(y)'" do
    expect(cmd.parse("foo(x) and bar(y)")).to eq({binary_op: "and", left: {funcall: "foo", funcall_args: {funcall_args_head: {tag_name: "x"}}}, right: {funcall: "bar", funcall_args: {funcall_args_head: {tag_name: "y"}}}})
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
