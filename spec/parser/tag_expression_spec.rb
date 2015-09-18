require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "tag expression" do
  let(:cmd) {
    Hotdog::Commands::Search.new(Hotdog::Application.new)
  }

  it "interprets tag with host" do
    expr = Hotdog::Commands::Search::TagExpressionNode.new("host", "foo", ":")
    q = [
      "SELECT hosts.id AS host_id FROM hosts",
        "WHERE hosts.name = ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({identifier: "host", separator: ":", attribute: "foo"})
  end

  it "interprets tag with identifier and attribute" do
    expr = Hotdog::Commands::Search::TagExpressionNode.new("foo", "bar", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name = ? AND tags.value = ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo", "bar"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({identifier: "foo", separator: ":", attribute: "bar"})
  end

  it "interprets tag with identifier with separator" do
    expr = Hotdog::Commands::Search::TagExpressionNode.new("foo", nil, ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name = ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({identifier: "foo", separator: ":"})
  end

  it "interprets tag with identifier without separator" do
    expr = Hotdog::Commands::Search::TagExpressionNode.new("foo", nil, nil)
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts.name = ? OR tags.name = ? OR tags.value = ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo", "foo", "foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({identifier: "foo"})
  end

  it "interprets tag with attribute with separator" do
    expr = Hotdog::Commands::Search::TagExpressionNode.new(nil, "foo", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.value = ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({separator: ":", attribute: "foo"})
  end

  it "interprets tag with attribute without separator" do
    expr = Hotdog::Commands::Search::TagExpressionNode.new(nil, "foo", nil)
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.value = ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({attribute: "foo"})
  end

  it "empty tag" do
    expr = Hotdog::Commands::Search::TagExpressionNode.new(nil, nil, nil)
    expect(expr.evaluate(cmd)).to eq([])
    expect(expr.dump).to eq({})
  end
end
