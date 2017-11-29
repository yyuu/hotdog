require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "tag glob expression" do
  let(:cmd) {
    Hotdog::Commands::Search.new(Hotdog::Application.new)
  }

  before(:each) do
    ENV["DATADOG_API_KEY"] = "DATADOG_API_KEY"
    ENV["DATADOG_APPLICATION_KEY"] = "DATADOG_APPLICATION_KEY"
  end

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
    expect(expr.dump).to eq({tagname_glob: "@host", separator: ":", tagvalue_glob: "foo*"})
  end

  it "interprets tag glob with tagname and tagvalue" do
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
    expect(expr.dump).to eq({tagname_glob: "foo*", separator: ":", tagvalue_glob: "bar*"})
  end

  it "interprets tag glob with tagname with separator" do
    expr = Hotdog::Expression::GlobTagnameNode.new("foo*", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE LOWER(tags.name) GLOB LOWER(?);",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo*"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tagname_glob: "foo*", separator: ":"})
  end

  it "interprets tag glob with tagname without separator" do
    expr = Hotdog::Expression::GlobHostOrTagNode.new("foo*", nil)
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
    expect(expr.dump).to eq({tagname_glob: "foo*"})
  end

  it "interprets tag glob with tagvalue with separator" do
    expr = Hotdog::Expression::GlobTagvalueNode.new("foo*", ":")
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
    expect(expr.dump).to eq({separator: ":", tagvalue_glob: "foo*"})
  end

  it "interprets tag glob with tagvalue without separator" do
    expr = Hotdog::Expression::GlobTagvalueNode.new("foo*", nil)
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
    expect(expr.dump).to eq({tagvalue_glob: "foo*"})
  end

  it "empty tag glob" do
    expr = Hotdog::Expression::GlobExpressionNode.new(nil, nil, nil)
    expect {
      expr.evaluate(cmd)
    }.to raise_error(NotImplementedError)
    expect(expr.dump).to eq({})
  end
end
