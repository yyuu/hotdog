require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "tag regexp expression" do
  let(:cmd) {
    Hotdog::Commands::Search.new(Hotdog::Application.new)
  }

  it "interprets tag regexp with host" do
    expr = Hotdog::Commands::Search::TagRegexpExpressionNode.new("host", "/foo/")
    q = [
      "SELECT hosts.id FROM hosts",
        "WHERE hosts.name REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
  end

  it "interprets tag regexp with identifier and attribute" do
    expr = Hotdog::Commands::Search::TagRegexpExpressionNode.new("/foo/", "/bar/")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name REGEXP ? AND tags.value REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo", "bar"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
  end

  it "interprets tag regexp with identifier" do
    expr = Hotdog::Commands::Search::TagRegexpExpressionNode.new("/foo/", nil)
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts.name REGEXP ? OR tags.name REGEXP ? OR tags.value REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo", "foo", "foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
  end

  it "interprets tag regexp with attribute" do
    expr = Hotdog::Commands::Search::TagRegexpExpressionNode.new(nil, "/foo/")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.value REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
  end
end
