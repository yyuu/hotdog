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
    expect(cmd.parse(":foo")).to eq({separator: ":", tagvalue: "foo"})
  end

  it "parses ':foo*'" do
    expect(cmd.parse(":foo*")).to eq({separator: ":", tagvalue_glob: "foo*"})
  end

  it "parses ':/foo/'" do
    expect(cmd.parse(":/foo/")).to eq({separator: ":", tagvalue_regexp: "/foo/"})
  end

  it "parses 'foo'" do
    expect(cmd.parse("foo")).to eq({tagname: "foo"})
  end

  it "parses 'foo:bar'" do
    expect(cmd.parse("foo:bar")).to eq({tagname: "foo", separator: ":", tagvalue: "bar"})
  end

  it "parses 'foo: bar'" do
    expect(cmd.parse("foo:bar")).to eq({tagname: "foo", separator: ":", tagvalue: "bar"})
  end

  it "parses 'foo :bar'" do
    expect(cmd.parse("foo:bar")).to eq({tagname: "foo", separator: ":", tagvalue: "bar"})
  end

  it "parses 'foo : bar'" do
    expect(cmd.parse("foo:bar")).to eq({tagname: "foo", separator: ":", tagvalue: "bar"})
  end

  it "parses 'foo:bar*'" do
    expect(cmd.parse("foo:bar*")).to eq({tagname: "foo", separator: ":", tagvalue_glob: "bar*"})
  end

  it "parses 'foo*'" do
    expect(cmd.parse("foo*")).to eq({tagname_glob: "foo*"})
  end

  it "parses 'foo*:bar'" do
    expect(cmd.parse("foo*:bar")).to eq({tagname_glob: "foo*", separator: ":", tagvalue: "bar"})
  end

  it "parses 'foo*:bar*'" do
    expect(cmd.parse("foo*:bar*")).to eq({tagname_glob: "foo*", separator: ":", tagvalue_glob: "bar*"})
  end

  it "parses '/foo/'" do
    expect(cmd.parse("/foo/")).to eq({tagname_regexp: "/foo/"})
  end

  it "parses '/foo/:/bar/'" do
    expect(cmd.parse("/foo/:/bar/")).to eq({tagname_regexp: "/foo/", separator: ":", tagvalue_regexp: "/bar/"})
  end

  it "parses '(foo)'" do
    expect(cmd.parse("(foo)")).to eq({tagname: "foo"})
  end

  it "parses '( foo )'" do
    expect(cmd.parse("( foo )")).to eq({tagname: "foo"})
  end

  it "parses ' ( foo ) '" do
    expect(cmd.parse(" ( foo ) ")).to eq({tagname: "foo"})
  end

  it "parses '((foo))'" do
    expect(cmd.parse("((foo))")).to eq({tagname: "foo"})
  end

  it "parses '(( foo ))'" do
    expect(cmd.parse("(( foo ))")).to eq({tagname: "foo"})
  end

  it "parses ' ( ( foo ) ) '" do
    expect(cmd.parse("( ( foo ) )")).to eq({tagname: "foo"})
  end

  it "parses 'tagname with prefix and'" do
    expect(cmd.parse("android")).to eq({tagname: "android"})
  end

  it "parses 'tagname with infix and'" do
    expect(cmd.parse("islander")).to eq({tagname: "islander"})
  end

  it "parses 'tagname with suffix and'" do
    expect(cmd.parse("mainland")).to eq({tagname: "mainland"})
  end

  it "parses 'tagname with prefix or'" do
    expect(cmd.parse("oreo")).to eq({tagname: "oreo"})
  end

  it "parses 'tagname with infix or'" do
    expect(cmd.parse("category")).to eq({tagname: "category"})
  end

  it "parses 'tagname with suffix or'" do
    expect(cmd.parse("imperator")).to eq({tagname: "imperator"})
  end

  it "parses 'tagname with prefix not'" do
    expect(cmd.parse("nothing")).to eq({tagname: "nothing"})
  end

  it "parses 'tagname with infix not'" do
    expect(cmd.parse("annotation")).to eq({tagname: "annotation"})
  end

  it "parses 'tagname with suffix not'" do
    expect(cmd.parse("forgetmenot")).to eq({tagname: "forgetmenot"})
  end

  it "parses 'foo bar'" do
    expect(cmd.parse("foo bar")).to eq({left: {tagname: "foo"}, binary_op: nil, right: {tagname: "bar"}})
  end

  it "parses 'foo bar baz'" do
    expect(cmd.parse("foo bar baz")).to eq({left: {tagname: "foo"}, binary_op: nil, right: {left: {tagname: "bar"}, binary_op: nil, right: {tagname: "baz"}}})
  end

  it "parses 'not foo'" do
    expect(cmd.parse("not foo")).to eq({unary_op: "not", expression: {tagname: "foo"}})
  end

  it "parses '! foo'" do
    expect(cmd.parse("! foo")).to eq({unary_op: "!", expression: {tagname: "foo"}})
  end

  it "parses '~ foo'" do
    expect(cmd.parse("~ foo")).to eq({unary_op: "~", expression: {tagname: "foo"}})
  end

  it "parses 'not(not foo)'" do
    expect(cmd.parse("not(not foo)")).to eq({unary_op: "not", expression: {unary_op: "not", expression: {tagname: "foo"}}})
  end

  it "parses '!(!foo)'" do
    expect(cmd.parse("!(!foo)")).to eq({unary_op: "!", expression: {unary_op: "!", expression: {tagname: "foo"}}})
  end

  it "parses '~(~foo)'" do
    expect(cmd.parse("~(~foo)")).to eq({unary_op: "~", expression: {unary_op: "~", expression: {tagname: "foo"}}})
  end

  it "parses 'not not foo'" do
    expect(cmd.parse("not not foo")).to eq({unary_op: "not", expression: {unary_op: "not", expression: {tagname: "foo"}}})
  end

  it "parses '!!foo'" do
    expect(cmd.parse("!! foo")).to eq({unary_op: "!", expression: {unary_op: "!", expression: {tagname: "foo"}}})
  end

  it "parses '! ! foo'" do
    expect(cmd.parse("!! foo")).to eq({unary_op: "!", expression: {unary_op: "!", expression: {tagname: "foo"}}})
  end

  it "parses '~~foo'" do
    expect(cmd.parse("~~ foo")).to eq({unary_op: "~", expression: {unary_op: "~", expression: {tagname: "foo"}}})
  end

  it "parses '~ ~ foo'" do
    expect(cmd.parse("~~ foo")).to eq({unary_op: "~", expression: {unary_op: "~", expression: {tagname: "foo"}}})
  end

  it "parses 'foo and bar'" do
    expect(cmd.parse("foo and bar")).to eq({left: {tagname: "foo"}, binary_op: "and", right: {tagname: "bar"}})
  end

  it "parses 'foo and bar and baz'" do
    expect(cmd.parse("foo and bar and baz")).to eq({left: {tagname: "foo"}, binary_op: "and", right: {left: {tagname: "bar"}, binary_op: "and", right: {tagname: "baz"}}})
  end

  it "parses 'foo&bar'" do
    expect(cmd.parse("foo&bar")).to eq({left: {tagname: "foo"}, binary_op: "&", right: {tagname: "bar"}})
  end

  it "parses 'foo & bar'" do
    expect(cmd.parse("foo & bar")).to eq({left: {tagname: "foo"}, binary_op: "&", right: {tagname: "bar"}})
  end

  it "parses 'foo&bar&baz'" do
    expect(cmd.parse("foo & bar & baz")).to eq({left: {tagname: "foo"}, binary_op: "&", right: {left: {tagname: "bar"}, binary_op: "&", right: {tagname: "baz"}}})
  end

  it "parses 'foo & bar & baz'" do
    expect(cmd.parse("foo & bar & baz")).to eq({left: {tagname: "foo"}, binary_op: "&", right: {left: {tagname: "bar"}, binary_op: "&", right: {tagname: "baz"}}})
  end

  it "parses 'foo&&bar'" do
    expect(cmd.parse("foo&&bar")).to eq({left: {tagname: "foo"}, binary_op: "&&", right: {tagname: "bar"}})
  end

  it "parses 'foo && bar'" do
    expect(cmd.parse("foo && bar")).to eq({left: {tagname: "foo"}, binary_op: "&&", right: {tagname: "bar"}})
  end

  it "parses 'foo&&bar&&baz'" do
    expect(cmd.parse("foo&&bar&&baz")).to eq({left: {tagname: "foo"}, binary_op: "&&", right: {left: {tagname: "bar"}, binary_op: "&&", right: {tagname: "baz"}}})
  end

  it "parses 'foo && bar && baz'" do
    expect(cmd.parse("foo && bar && baz")).to eq({left: {tagname: "foo"}, binary_op: "&&", right: {left: {tagname: "bar"}, binary_op: "&&", right: {tagname: "baz"}}})
  end

  it "parses 'foo or bar'" do
    expect(cmd.parse("foo or bar")).to eq({left: {tagname: "foo"}, binary_op: "or", right: {tagname: "bar"}})
  end

  it "parses 'foo or bar or baz'" do
    expect(cmd.parse("foo or bar or baz")).to eq({left: {tagname: "foo"}, binary_op: "or", right: {left: {tagname: "bar"}, binary_op: "or", right: {tagname: "baz"}}})
  end

  it "parses 'foo|bar'" do
    expect(cmd.parse("foo|bar")).to eq({left: {tagname: "foo"}, binary_op: "|", right: {tagname: "bar"}})
  end

  it "parses 'foo | bar'" do
    expect(cmd.parse("foo | bar")).to eq({left: {tagname: "foo"}, binary_op: "|", right: {tagname: "bar"}})
  end

  it "parses 'foo|bar|baz'" do
    expect(cmd.parse("foo|bar|baz")).to eq({left: {tagname: "foo"}, binary_op: "|", right: {left: {tagname: "bar"}, binary_op: "|", right: {tagname: "baz"}}})
  end

  it "parses 'foo | bar | baz'" do
    expect(cmd.parse("foo | bar | baz")).to eq({left: {tagname: "foo"}, binary_op: "|", right: {left: {tagname: "bar"}, binary_op: "|", right: {tagname: "baz"}}})
  end

  it "parses 'foo||bar'" do
    expect(cmd.parse("foo||bar")).to eq({left: {tagname: "foo"}, binary_op: "||", right: {tagname: "bar"}})
  end

  it "parses 'foo || bar'" do
    expect(cmd.parse("foo || bar")).to eq({left: {tagname: "foo"}, binary_op: "||", right: {tagname: "bar"}})
  end

  it "parses 'foo||bar||baz'" do
    expect(cmd.parse("foo||bar||baz")).to eq({left: {tagname: "foo"}, binary_op: "||", right: {left: {tagname: "bar"}, binary_op: "||", right: {tagname: "baz"}}})
  end

  it "parses 'foo || bar || baz'" do
    expect(cmd.parse("foo || bar || baz")).to eq({left: {tagname: "foo"}, binary_op: "||", right: {left: {tagname: "bar"}, binary_op: "||", right: {tagname: "baz"}}})
  end

  it "parses '(foo and bar) or baz'" do
    expect(cmd.parse("(foo and bar) or baz")).to eq({left: {left: {tagname: "foo"}, binary_op: "and", right: {tagname: "bar"}}, binary_op: "or", right: {tagname: "baz"}})
  end

  it "parses 'foo and (bar or baz)'" do
    expect(cmd.parse("foo and (bar or baz)")).to eq({left: {tagname: "foo"}, binary_op: "and", right: {left: {tagname: "bar"}, binary_op: "or", right: {tagname: "baz"}}})
  end

  it "parses 'not foo and bar'" do
    expect(cmd.parse("not foo and bar")).to eq({unary_op: "not", expression: {left: {tagname: "foo"}, binary_op: "and", right: {tagname: "bar"}}})
  end

  it "parses '! foo and bar'" do
    expect(cmd.parse("! foo and bar")).to eq({left: {unary_op: "!", expression: {tagname: "foo"}}, binary_op: "and", right: {tagname: "bar"}})
  end

  it "parses 'not foo && bar'" do
    expect(cmd.parse("not foo && bar")).to eq({unary_op: "not", expression: {left: {tagname: "foo"}, binary_op: "&&", right: {tagname: "bar"}}})
  end

  it "parses '! foo && bar'" do
    expect(cmd.parse("! foo && bar")).to eq({left: {unary_op: "!", expression: {tagname: "foo"}}, binary_op: "&&", right: {tagname: "bar"}})
  end

  it "parses 'f(x)'" do
    expect(cmd.parse("f(x)")).to eq({funcall: "f", funcall_args: {funcall_args_head: {tagname: "x"}}})
  end

  it "parses 'f(x, \"y\")'" do
    expect(cmd.parse("f(x, \"y\")")).to eq({funcall: "f", funcall_args: {funcall_args_head: {tagname: "x"}, funcall_args_tail: {funcall_args_head: {string: "\"y\""}}}})
  end

  it "parses 'f(x, \"y\", /z/)'" do
    expect(cmd.parse("f(x, \"y\", /z/)")).to eq({funcall: "f", funcall_args: {funcall_args_head: {tagname: "x"}, funcall_args_tail: {funcall_args_head: {string: "\"y\""}, funcall_args_tail: {funcall_args_head: {regexp: "/z/"}}}}})
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
    expect(cmd.parse("foo and bar(y)")).to eq({binary_op: "and", left: {tagname: "foo"}, right: {funcall: "bar", funcall_args: {funcall_args_head: {tagname: "y"}}}})
  end

  it "parses 'foo(x) and bar(y)'" do
    expect(cmd.parse("foo(x) and bar(y)")).to eq({binary_op: "and", left: {funcall: "foo", funcall_args: {funcall_args_head: {tagname: "x"}}}, right: {funcall: "bar", funcall_args: {funcall_args_head: {tagname: "y"}}}})
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
