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
    expr = Hotdog::Expression::RegexpHostNode.new("foo", ":")
    q = [
      "SELECT hosts.id AS host_id FROM hosts",
        "WHERE hosts.name REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tag_name_regexp: "host", separator: ":", tag_value_regexp: "foo"})
  end

  it "interprets tag regexp with tag_name and tag_value" do
    expr = Hotdog::Expression::RegexpTagNode.new("foo", "bar", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name REGEXP ? AND tags.value REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo", "bar"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tag_name_regexp: "foo", separator: ":", tag_value_regexp: "bar"})
  end

  it "interprets tag regexp with tag_name with separator" do
    expr = Hotdog::Expression::RegexpTagNameNode.new("foo", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tag_name_regexp: "foo", separator: ":"})
  end

  it "interprets tag regexp with tag_name without separator" do
    expr = Hotdog::Expression::RegexpHostOrTagNode.new("foo", nil)
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
    expect(expr.dump).to eq({tag_name_regexp: "foo"})
  end

  it "interprets tag regexp with tag_value with separator" do
    expr = Hotdog::Expression::RegexpTagValueNode.new("foo", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts.name REGEXP ? OR tags.value REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo", "foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({separator: ":", tag_value_regexp: "foo"})
  end

  it "interprets tag regexp with tag_value without separator" do
    expr = Hotdog::Expression::RegexpTagValueNode.new("foo", nil)
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts.name REGEXP ? OR tags.value REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo", "foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tag_value_regexp: "foo"})
  end

  it "empty tag regexp" do
    expr = Hotdog::Expression::RegexpExpressionNode.new(nil, nil, nil)
    expect {
      expr.evaluate(cmd)
    }.to raise_error(NotImplementedError)
    expect(expr.dump).to eq({})
  end
end
