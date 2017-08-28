require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "tag glob expression" do
  3.times do |o|
    it "interprets tag glob with host (#{o})" do
      expr = Hotdog::Expression::GlobHostNode.new("foo*", ":")
      expect(optimize_n(o+1, expr).dump).to eq({
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

    it "interprets tag glob with tagname and tagvalue (#{o})" do
      expr = Hotdog::Expression::GlobTagNode.new("foo*", "bar*", ":")
      expect(optimize_n(o+1, expr).dump).to eq({
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

    it "interprets tag glob with tagname with separator (#{o})" do
      expr = Hotdog::Expression::GlobTagnameNode.new("foo*", ":")
      expect(optimize_n(o+1, expr).dump).to eq({
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

    it "interprets tag glob with tagname without separator (#{o})" do
      expr = Hotdog::Expression::GlobHostOrTagNode.new("foo*", nil)
      expect(optimize_n(o+1, expr).dump).to eq({
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

    it "interprets tag glob with tagvalue with separator (#{o})" do
      expr = Hotdog::Expression::GlobTagvalueNode.new("foo*", ":")
      expect(optimize_n(o+1, expr).dump).to eq({
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

    it "interprets tag glob with tagvalue without separator (#{o})" do
      expr = Hotdog::Expression::GlobTagvalueNode.new("foo*", nil)
      expect(optimize_n(o+1, expr).dump).to eq({
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
end
