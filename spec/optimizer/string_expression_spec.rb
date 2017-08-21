require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "tag expression" do
  let(:cmd) {
    Hotdog::Commands::Search.new(Hotdog::Application.new)
  }

  before(:each) do
    ENV["DATADOG_API_KEY"] = "DATADOG_API_KEY"
    ENV["DATADOG_APPLICATION_KEY"] = "DATADOG_APPLICATION_KEY"
  end

  it "interprets tag with host" do
    expr = Hotdog::Expression::StringHostNode.new("foo", ":")
    q = [
      "SELECT hosts.id AS host_id FROM hosts",
        "WHERE hosts.name = ?;",
    ]
    expect(expr.optimize.dump).to eq({tagname: "host", separator: ":", tagvalue: "foo"})
  end

  it "interprets tag with tagname and tagvalue" do
    expr = Hotdog::Expression::StringTagNode.new("foo", "bar", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name = ? AND tags.value = ?;",
    ]
    expect(expr.optimize.dump).to eq({tagname: "foo", separator: ":", tagvalue: "bar"})
  end

  it "interprets tag with tagname with separator" do
    expr = Hotdog::Expression::StringTagnameNode.new("foo", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE tags.name = ?;",
    ]
    expect(expr.optimize.dump).to eq({tagname: "foo", separator: ":"})
  end

  it "interprets tag with tagname without separator" do
    expr = Hotdog::Expression::StringHostOrTagNode.new("foo", nil)
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts.name = ? OR tags.name = ? OR tags.value = ?;",
    ]
    expect(expr.optimize.dump).to eq({tagname: "foo"})
  end

  it "interprets tag with tagvalue with separator" do
    expr = Hotdog::Expression::StringTagvalueNode.new("foo", ":")
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts.name = ? OR tags.value = ?;",
    ]
    expect(expr.optimize.dump).to eq({separator: ":", tagvalue: "foo"})
  end

  it "interprets tag with tagvalue without separator" do
    expr = Hotdog::Expression::StringTagvalueNode.new("foo", nil)
    q = [
      "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
        "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts.name = ? OR tags.value = ?;",
    ]
    expect(expr.optimize.dump).to eq({tagvalue: "foo"})
  end

# it "empty tag" do
#   expr = Hotdog::Expression::StringExpressionNode.new(nil, nil, nil)
#   expect {
#     expr.evaluate(cmd)
#   }.to raise_error(NotImplementedError)
#   expect(expr.dump).to eq({})
# end
end
