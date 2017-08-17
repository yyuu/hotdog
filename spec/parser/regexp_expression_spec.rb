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
    expect(expr.dump).to eq({tagname_regexp: "host", separator: ":", tagvalue_regexp: "foo"})
  end

  it "interprets tag regexp with tagname and tagvalue" do
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
    expect(expr.dump).to eq({tagname_regexp: "foo", separator: ":", tagvalue_regexp: "bar"})
  end

  it "interprets tag regexp with tagname with separator" do
    expr = Hotdog::Expression::RegexpTagnameNode.new("foo", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name REGEXP ?;",
    ]
    allow(cmd).to receive(:execute).with(q.join(" "), ["foo"]) {
      [[1], [2], [3]]
    }
    expect(expr.evaluate(cmd)).to eq([1, 2, 3])
    expect(expr.dump).to eq({tagname_regexp: "foo", separator: ":"})
  end

  it "interprets tag regexp with tagname without separator" do
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
    expect(expr.dump).to eq({tagname_regexp: "foo"})
  end

  it "interprets tag regexp with tagvalue with separator" do
    expr = Hotdog::Expression::RegexpTagvalueNode.new("foo", ":")
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
    expect(expr.dump).to eq({separator: ":", tagvalue_regexp: "foo"})
  end

  it "interprets tag regexp with tagvalue without separator" do
    expr = Hotdog::Expression::RegexpTagvalueNode.new("foo", nil)
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
    expect(expr.dump).to eq({tagvalue_regexp: "foo"})
  end

  it "empty tag regexp" do
    expr = Hotdog::Expression::RegexpExpressionNode.new(nil, nil, nil)
    expect {
      expr.evaluate(cmd)
    }.to raise_error(NotImplementedError)
    expect(expr.dump).to eq({})
  end
end
