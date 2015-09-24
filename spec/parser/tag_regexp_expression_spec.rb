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
    expr = Hotdog::Commands::Search::RegexpHostNode.new("foo", ":")
    q = [
      "SELECT hosts.id AS host_id FROM hosts",
        "WHERE hosts.name REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({identifier_regexp: "host", separator: ":", attribute_regexp: "foo"})
  end

  it "interprets tag regexp with identifier and attribute" do
    expr = Hotdog::Commands::Search::RegexpTagNode.new("foo", "bar", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name REGEXP ? AND tags.value REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo", "bar"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({identifier_regexp: "foo", separator: ":", attribute_regexp: "bar"})
  end

  it "interprets tag regexp with identifier with separator" do
    expr = Hotdog::Commands::Search::RegexpTagNameNode.new("foo", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({identifier_regexp: "foo", separator: ":"})
  end

  it "interprets tag regexp with identifier without separator" do
    expr = Hotdog::Commands::Search::RegexpExpressionNode.new("foo", nil, nil)
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
    expect(expr.dump).to eq({identifier_regexp: "foo"})
  end

  it "interprets tag regexp with attribute with separator" do
    expr = Hotdog::Commands::Search::RegexpTagValueNode.new("foo", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.value REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({separator: ":", attribute_regexp: "foo"})
  end

  it "interprets tag regexp with attribute without separator" do
    expr = Hotdog::Commands::Search::RegexpTagValueNode.new("foo", nil)
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.value REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({attribute_regexp: "foo"})
  end

  it "empty tag regexp" do
    expr = Hotdog::Commands::Search::RegexpExpressionNode.new(nil, nil, nil)
    expect(expr.evaluate(cmd)).to eq([])
    expect(expr.dump).to eq({})
  end
end
