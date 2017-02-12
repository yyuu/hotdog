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
    expr = Hotdog::Expression::StringHostNode.new("foo", ":")
    q = [
      "SELECT hosts.id AS host_id FROM hosts",
        "WHERE hosts.name = ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tag_name: "host", separator: ":", tag_value: "foo"})
  end

  it "interprets tag with tag_name and tag_value" do
    expr = Hotdog::Expression::StringTagNode.new("foo", "bar", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name = ? AND tags.value = ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo", "bar"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tag_name: "foo", separator: ":", tag_value: "bar"})
  end

  it "interprets tag with tag_name with separator" do
    expr = Hotdog::Expression::StringTagNameNode.new("foo", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name = ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tag_name: "foo", separator: ":"})
  end

  it "interprets tag with tag_name without separator" do
    expr = Hotdog::Expression::StringHostOrTagNode.new("foo", nil)
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
    expect(expr.dump).to eq({tag_name: "foo"})
  end

  it "interprets tag with tag_value with separator" do
    expr = Hotdog::Expression::StringTagValueNode.new("foo", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts.name = ? OR tags.value = ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo", "foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({separator: ":", tag_value: "foo"})
  end

  it "interprets tag with tag_value without separator" do
    expr = Hotdog::Expression::StringTagValueNode.new("foo", nil)
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts.name = ? OR tags.value = ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo", "foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tag_value: "foo"})
  end

  it "empty tag" do
    expr = Hotdog::Expression::StringExpressionNode.new(nil, nil, nil)
    expect {
      expr.evaluate(cmd)
    }.to raise_error(NotImplementedError)
    expect(expr.dump).to eq({})
  end
end
