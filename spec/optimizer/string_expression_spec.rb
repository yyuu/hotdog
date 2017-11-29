require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "tag expression" do
  3.times do |o|
    it "interprets tag with host (#{o})" do
      expr = Hotdog::Expression::StringHostNode.new("foo", ":")
      expect(optimize_n(o+1, expr).dump).to eq({
        tagname: "@host",
        separator: ":",
        tagvalue: "foo",
        fallback: {
          query: [
            "SELECT hosts.id AS host_id FROM hosts",
            "WHERE LOWER(hosts.name) GLOB LOWER(?);",
          ].join(" "),
          values: ["*foo*"],
        },
      })
    end

    it "interprets tag with tagname and tagvalue (#{o})" do
      expr = Hotdog::Expression::StringTagNode.new("foo", "bar", ":")
      expect(optimize_n(o+1, expr).dump).to eq({
        tagname: "foo",
        separator: ":",
        tagvalue: "bar",
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

    it "interprets tag with tagname with separator (#{o})" do
      expr = Hotdog::Expression::StringTagnameNode.new("foo", ":")
      expect(optimize_n(o+1, expr).dump).to eq({
        tagname: "foo",
        separator: ":",
        fallback: {
          query: [
            "SELECT DISTINCT hosts_tags.host_id FROM hosts_tags",
            "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
            "WHERE LOWER(tags.name) GLOB LOWER(?);",
          ].join(" "),
          values: ["*foo*"],
        }
      })
    end

    it "interprets tag with tagname without separator (#{o})" do
      expr = Hotdog::Expression::StringHostOrTagNode.new("foo", nil)
      expect(optimize_n(o+1, expr).dump).to eq({
        tagname: "foo",
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

    it "interprets tag with tagvalue with separator (#{o})" do
      expr = Hotdog::Expression::StringTagvalueNode.new("foo", ":")
      expect(optimize_n(o+1, expr).dump).to eq({
        tagvalue: "foo",
        separator: ":",
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

    it "interprets tag with tagvalue without separator (#{o})" do
      expr = Hotdog::Expression::StringTagvalueNode.new("foo", nil)
      expect(optimize_n(o+1, expr).dump).to eq({
        tagvalue: "foo",
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
  end
end
