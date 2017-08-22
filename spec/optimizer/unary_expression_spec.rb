require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "unary expression" do
  it "should be everything" do
    expr = Hotdog::Expression::UnaryExpressionNode.new("NOT", Hotdog::Expression::NothingNode.new())
    expect(expr.optimize.dump).to eq({
      query: "SELECT id AS host_id FROM hosts;",
      values: [],
    })
  end

  it "should be nothing" do
    expr = Hotdog::Expression::UnaryExpressionNode.new("NOT", Hotdog::Expression::EverythingNode.new())
    expect(expr.optimize.dump).to eq({
      query: "SELECT NULL AS host_id WHERE host_id NOT NULL;",
      values: [],
    })
  end
end
