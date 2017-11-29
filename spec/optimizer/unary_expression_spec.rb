require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "unary expression" do
  3.times do |o|
    it "NOT nothing should return everything (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new("NOT", Hotdog::Expression::NothingNode.new())
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT id AS host_id FROM hosts;",
        values: [],
      })
    end

    it "NOT everything should return nothing (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new("NOT", Hotdog::Expression::EverythingNode.new())
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT NULL AS host_id WHERE host_id NOT NULL;",
        values: [],
      })
    end

    it "NOT NOT nothing should return nothing (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOT",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOT",
          Hotdog::Expression::NothingNode.new(),
        ),
      )
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT NULL AS host_id WHERE host_id NOT NULL;",
        values: [],
      })
    end

    it "NOT NOT everything should return everything (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOT",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOT",
          Hotdog::Expression::EverythingNode.new(),
        ),
      )
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT id AS host_id FROM hosts;",
        values: [],
      })
    end

    it "NOT NOT NOT nothing should return everything (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOT",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOT",
          Hotdog::Expression::UnaryExpressionNode.new(
            "NOT",
            Hotdog::Expression::NothingNode.new(),
          ),
        ),
      )
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT id AS host_id FROM hosts;",
        values: [],
      })
    end

    it "NOT NOT NOT everything should return nothing (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOT",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOT",
          Hotdog::Expression::UnaryExpressionNode.new(
            "NOT",
            Hotdog::Expression::EverythingNode.new(),
          ),
        ),
      )
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT NULL AS host_id WHERE host_id NOT NULL;",
        values: [],
      })
    end

    it "NOT host should return everything except the host (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOT",
        Hotdog::Expression::StringHostNode.new("foo", ":"),
      )
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT id AS host_id FROM hosts EXCEPT SELECT hosts.id AS host_id FROM hosts WHERE hosts.name = ?;",
        values: ["foo"],
      })
    end

    it "NOT NOT host should return the host (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOT",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOT",
          Hotdog::Expression::StringHostNode.new("foo", ":"),
        ),
      )
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

    it "NOT NOT NOT host should return everything except the host (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOT",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOT",
          Hotdog::Expression::UnaryExpressionNode.new(
            "NOT",
            Hotdog::Expression::StringHostNode.new("foo", ":"),
          ),
        ),
      )
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT id AS host_id FROM hosts EXCEPT SELECT hosts.id AS host_id FROM hosts WHERE hosts.name = ?;",
        values: ["foo"],
      })
    end

    it "NOOP host should return the host (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOOP",
        Hotdog::Expression::StringHostNode.new("foo", ":"),
      )
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

    it "NOOP NOOP host should return the host (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOOP",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOOP",
          Hotdog::Expression::StringHostNode.new("foo", ":"),
        ),
      )
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

    it "NOOP NOOP NOOP host should return the host (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOOP",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOOP",
          Hotdog::Expression::UnaryExpressionNode.new(
            "NOOP",
            Hotdog::Expression::StringHostNode.new("foo", ":"),
          ),
        ),
      )
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

    it "NOT NOOP NOOP host should return everything except the host (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOT",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOOP",
          Hotdog::Expression::UnaryExpressionNode.new(
            "NOOP",
            Hotdog::Expression::StringHostNode.new("foo", ":"),
          ),
        ),
      )
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT id AS host_id FROM hosts EXCEPT SELECT hosts.id AS host_id FROM hosts WHERE hosts.name = ?;",
        values: ["foo"],
      })
    end

    it "NOOP NOT NOOP host should return everything except the host (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOOP",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOT",
          Hotdog::Expression::UnaryExpressionNode.new(
            "NOOP",
            Hotdog::Expression::StringHostNode.new("foo", ":"),
          ),
        ),
      )
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT id AS host_id FROM hosts EXCEPT SELECT hosts.id AS host_id FROM hosts WHERE hosts.name = ?;",
        values: ["foo"],
      })
    end

    it "NOOP NOOP NOT host should return everything except the host (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOOP",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOOP",
          Hotdog::Expression::UnaryExpressionNode.new(
            "NOT",
            Hotdog::Expression::StringHostNode.new("foo", ":"),
          ),
        ),
      )
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT id AS host_id FROM hosts EXCEPT SELECT hosts.id AS host_id FROM hosts WHERE hosts.name = ?;",
        values: ["foo"],
      })
    end

    it "NOOP NOT NOT host should return everything except the host (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOT",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOT",
          Hotdog::Expression::UnaryExpressionNode.new(
            "NOOP",
            Hotdog::Expression::StringHostNode.new("foo", ":"),
          ),
        ),
      )
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

    it "NOT NOOP NOT host should return everything except the host (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOT",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOOP",
          Hotdog::Expression::UnaryExpressionNode.new(
            "NOT",
            Hotdog::Expression::StringHostNode.new("foo", ":"),
          ),
        ),
      )
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

    it "NOT NOT NOOP host should return everything except the host (#{o})" do
      expr = Hotdog::Expression::UnaryExpressionNode.new(
        "NOT",
        Hotdog::Expression::UnaryExpressionNode.new(
          "NOT",
          Hotdog::Expression::UnaryExpressionNode.new(
            "NOOP",
            Hotdog::Expression::StringHostNode.new("foo", ":"),
          ),
        ),
      )
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
  end
end
