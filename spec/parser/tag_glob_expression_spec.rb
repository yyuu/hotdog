require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "tag glob expression" do
  let(:cmd) {
    Hotdog::Commands::Search.new(Hotdog::Application.new)
  }

  it "interprets tag glob with host" do
    expr = Hotdog::Commands::Search::TagGlobExpressionNode.new("host", "foo*", ":")
    q = [
      "SELECT hosts.id AS host_id FROM hosts",
        "WHERE hosts.name GLOB ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo*"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
  end

  it "interprets tag glob with identifier and attribute" do
    expr = Hotdog::Commands::Search::TagGlobExpressionNode.new("foo*", "bar*", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name GLOB ? AND tags.value GLOB ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo*", "bar*"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
  end

  it "interprets tag glob with identifier with separator" do
    expr = Hotdog::Commands::Search::TagGlobExpressionNode.new("foo*", nil, ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name GLOB ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo*"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
  end

  it "interprets tag glob with identifier without separator" do
    expr = Hotdog::Commands::Search::TagGlobExpressionNode.new("foo*", nil, nil)
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts.name GLOB ? OR tags.name GLOB ? OR tags.value GLOB ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo*", "foo*", "foo*"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
  end

  it "interprets tag glob with attribute with separator" do
    expr = Hotdog::Commands::Search::TagGlobExpressionNode.new(nil, "foo*", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.value GLOB ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo*"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
  end

  it "interprets tag glob with attribute without separator" do
    expr = Hotdog::Commands::Search::TagGlobExpressionNode.new(nil, "foo*", nil)
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.value GLOB ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo*"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
  end
end
