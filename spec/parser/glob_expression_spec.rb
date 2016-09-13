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
    expr = Hotdog::Expression::GlobHostNode.new("foo*", ":")
    q = [
      "SELECT hosts.id AS host_id FROM hosts",
        "WHERE LOWER(hosts.name) GLOB LOWER(?);",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo*"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tag_name_glob: "host", separator: ":", tag_value_glob: "foo*"})
  end

  it "interprets tag glob with tag_name and tag_value" do
    expr = Hotdog::Expression::GlobTagNode.new("foo*", "bar*", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE LOWER(tags.name) GLOB LOWER(?) AND LOWER(tags.value) GLOB LOWER(?);",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo*", "bar*"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tag_name_glob: "foo*", separator: ":", tag_value_glob: "bar*"})
  end

  it "interprets tag glob with tag_name with separator" do
    expr = Hotdog::Expression::GlobTagNameNode.new("foo*", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE LOWER(tags.name) GLOB LOWER(?);",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo*"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tag_name_glob: "foo*", separator: ":"})
  end

  it "interprets tag glob with tag_name without separator" do
    expr = Hotdog::Expression::GlobNode.new("foo*", nil)
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?);",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo*", "foo*", "foo*"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tag_name_glob: "foo*"})
  end

  it "interprets tag glob with tag_value with separator" do
    expr = Hotdog::Expression::GlobTagValueNode.new("foo*", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?);",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo*", "foo*"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({separator: ":", tag_value_glob: "foo*"})
  end

  it "interprets tag glob with tag_value without separator" do
    expr = Hotdog::Expression::GlobTagValueNode.new("foo*", nil)
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?);",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo*", "foo*"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tag_value_glob: "foo*"})
  end

  it "empty tag glob" do
    expr = Hotdog::Expression::GlobExpressionNode.new(nil, nil, nil)
    expect {
      expr.evaluate(cmd)
    }.to raise_error(NotImplementedError)
    expect(expr.dump).to eq({})
  end
end
