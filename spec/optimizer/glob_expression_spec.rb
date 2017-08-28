require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "tag glob expression" do
  it "interprets tag glob with host" do
    expr = Hotdog::Expression::GlobHostNode.new("foo*", ":")
    expect(expr.optimize.optimize.optimize.dump).to eq({
      tagname_glob: "host",
      separator: ":",
      tagvalue_glob: "foo*",
      fallback: {
        query: [
          "SELECT hosts.id AS host_id FROM hosts",
          "WHERE LOWER(hosts.name) GLOB LOWER(?);",
        ].join(" "),
        values: ["*foo*"],
      },
    })
  end

  it "interprets tag glob with tagname and tagvalue" do
    expr = Hotdog::Expression::GlobTagNode.new("foo*", "bar*", ":")
    expect(expr.optimize.optimize.optimize.dump).to eq({
      tagname_glob: "foo*",
      separator: ":",
      tagvalue_glob: "bar*",
      fallback: {
        query: [
          "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
          "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE LOWER(tags.name) GLOB LOWER(?) AND LOWER(tags.value) GLOB LOWER(?);",
        ].join(" "),
        values: ["*foo*", "*bar*"],
      },
    })
  end

  it "interprets tag glob with tagname with separator" do
    expr = Hotdog::Expression::GlobTagnameNode.new("foo*", ":")
    expect(expr.optimize.optimize.optimize.dump).to eq({
      tagname_glob: "foo*",
      separator: ":",
      fallback: {
        query: [
          "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
          "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE LOWER(tags.name) GLOB LOWER(?);",
        ].join(" "),
        values: ["*foo*"],
      },
    })
  end

  it "interprets tag glob with tagname without separator" do
    expr = Hotdog::Expression::GlobHostOrTagNode.new("foo*", nil)
    expect(expr.optimize.optimize.optimize.dump).to eq({
      tagname_glob: "foo*",
      fallback: {
        query: [
          "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
          "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
          "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?);",
        ].join(" "),
        values: ["*foo*", "*foo*", "*foo*"],
      },
    })
  end

  it "interprets tag glob with tagvalue with separator" do
    expr = Hotdog::Expression::GlobTagvalueNode.new("foo*", ":")
    expect(expr.optimize.optimize.optimize.dump).to eq({
      separator: ":",
      tagvalue_glob: "foo*",
      fallback: {
        query: [
          "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
          "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
          "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?);",
        ].join(" "),
        values: ["*foo*", "*foo*"],
      },
    })
  end

  it "interprets tag glob with tagvalue without separator" do
    expr = Hotdog::Expression::GlobTagvalueNode.new("foo*", nil)
    expect(expr.optimize.optimize.optimize.dump).to eq({
      tagvalue_glob: "foo*",
      fallback: {
        query: [
          "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
          "INNER JOIN hosts ON hosts_tags.host_id = hosts.id",
          "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE LOWER(hosts.name) GLOB LOWER(?) OR LOWER(tags.value) GLOB LOWER(?);",
        ].join(" "),
        values: ["*foo*", "*foo*"],
      }
    })
  end
end
