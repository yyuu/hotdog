require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "tag regexp expression" do
  it "interprets tag regexp with host" do
    expr = Hotdog::Expression::RegexpHostNode.new("foo", ":")
    expect(expr.optimize.dump).to eq({
      tagname_regexp: "host",
       separator: ":",
       tagvalue_regexp: "foo",
    })
  end

  it "interprets tag regexp with tagname and tagvalue" do
    expr = Hotdog::Expression::RegexpTagNode.new("foo", "bar", ":")
    expect(expr.optimize.dump).to eq({
      tagname_regexp: "foo",
      separator: ":",
      tagvalue_regexp: "bar",
    })
  end

  it "interprets tag regexp with tagname with separator" do
    expr = Hotdog::Expression::RegexpTagnameNode.new("foo", ":")
    expect(expr.optimize.dump).to eq({
      tagname_regexp: "foo",
      separator: ":",
    })
  end

  it "interprets tag regexp with tagname without separator" do
    expr = Hotdog::Expression::RegexpHostOrTagNode.new("foo", nil)
    expect(expr.optimize.dump).to eq({
      tagname_regexp: "foo",
    })
  end

  it "interprets tag regexp with tagvalue with separator" do
    expr = Hotdog::Expression::RegexpTagvalueNode.new("foo", ":")
    expect(expr.optimize.dump).to eq({
      separator: ":",
      tagvalue_regexp: "foo",
    })
  end

  it "interprets tag regexp with tagvalue without separator" do
    expr = Hotdog::Expression::RegexpTagvalueNode.new("foo", nil)
    expect(expr.optimize.dump).to eq({
      tagvalue_regexp: "foo",
    })
  end
end
