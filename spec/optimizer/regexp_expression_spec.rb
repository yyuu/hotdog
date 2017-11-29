require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"
require "parslet"

describe "tag regexp expression" do
  3.times do |o|
    it "interprets tag regexp with host (#{o})" do
      expr = Hotdog::Expression::RegexpHostNode.new("foo", ":")
      expect(optimize_n(o+1, expr).dump).to eq({
        tagname_regexp: "@host",
         separator: ":",
         tagvalue_regexp: "foo",
      })
    end

    it "interprets tag regexp with tagname and tagvalue (#{o})" do
      expr = Hotdog::Expression::RegexpTagNode.new("foo", "bar", ":")
      expect(optimize_n(o+1, expr).dump).to eq({
        tagname_regexp: "foo",
        separator: ":",
        tagvalue_regexp: "bar",
      })
    end

    it "interprets tag regexp with tagname with separator (#{o})" do
      expr = Hotdog::Expression::RegexpTagnameNode.new("foo", ":")
      expect(optimize_n(o+1, expr).dump).to eq({
        tagname_regexp: "foo",
        separator: ":",
      })
    end

    it "interprets tag regexp with tagname without separator (#{o})" do
      expr = Hotdog::Expression::RegexpHostOrTagNode.new("foo", nil)
      expect(optimize_n(o+1, expr).dump).to eq({
        tagname_regexp: "foo",
      })
    end

    it "interprets tag regexp with tagvalue with separator (#{o})" do
      expr = Hotdog::Expression::RegexpTagvalueNode.new("foo", ":")
      expect(optimize_n(o+1, expr).dump).to eq({
        separator: ":",
        tagvalue_regexp: "foo",
      })
    end

    it "interprets tag regexp with tagvalue without separator (#{o})" do
      expr = Hotdog::Expression::RegexpTagvalueNode.new("foo", nil)
      expect(optimize_n(o+1, expr).dump).to eq({
        tagvalue_regexp: "foo",
      })
    end
  end
end
