require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "binary expression" do
  3.times do |o|
    it "everything AND x should return x (#{o})" do
      expr = Hotdog::Expression::BinaryExpressionNode.new("AND", Hotdog::Expression::EverythingNode.new(), Hotdog::Expression::NothingNode.new())
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT NULL AS host_id WHERE host_id NOT NULL;",
        values: [],
      })
    end

    it "nothing AND x should return nothing (#{o})" do
      expr = Hotdog::Expression::BinaryExpressionNode.new("AND", Hotdog::Expression::NothingNode.new(), Hotdog::Expression::EverythingNode.new())
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT NULL AS host_id WHERE host_id NOT NULL;",
        values: [],
      })
    end

    it "everything OR x should return everything (#{o})" do
      expr = Hotdog::Expression::BinaryExpressionNode.new("OR", Hotdog::Expression::EverythingNode.new(), Hotdog::Expression::NothingNode.new())
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT id AS host_id FROM hosts;",
        values: [],
      })
    end

    it "nothing OR x should return x (#{o})" do
      expr = Hotdog::Expression::BinaryExpressionNode.new("OR", Hotdog::Expression::NothingNode.new(), Hotdog::Expression::EverythingNode.new())
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT id AS host_id FROM hosts;",
        values: [],
      })
    end

    it "everything XOR everything should return nothing (#{o})" do
      expr = Hotdog::Expression::BinaryExpressionNode.new("XOR", Hotdog::Expression::EverythingNode.new(), Hotdog::Expression::EverythingNode.new())
      expect(optimize_n(o+1, expr).dump).to eq({
        query: "SELECT NULL AS host_id WHERE host_id NOT NULL;",
        values: [],
      })
    end
  end
end
