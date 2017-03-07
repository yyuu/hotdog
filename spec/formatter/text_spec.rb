require "spec_helper"
require "hotdog/formatters"
require "hotdog/formatters/text"

describe "text" do
  let(:fmt) {
    Hotdog::Formatters::Text.new
  }

  it "generates text (print0) without headers" do
    options = {
      headers: false,
      print0: true,
      print1: false,
      print2: false,
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq("foo aaa 1\0bar bbb 2\0baz ccc 3")
  end

  it "generates text (print0) with headers" do
    options = {
      headers: true,
      fields: ["key1", "key2", "val1"],
      print0: true,
      print1: false,
      print2: false,
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq("foo aaa 1\0bar bbb 2\0baz ccc 3")
  end

  it "generates text (print1) without headers" do
    options = {
      headers: false,
      print0: false,
      print1: true,
      print2: false,
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq(<<-EOS)
foo aaa 1
bar bbb 2
baz ccc 3
    EOS
  end

  it "generates text (print1) with headers" do
    options = {
      headers: true,
      fields: ["key1", "key2", "val1"],
      print0: false,
      print1: true,
      print2: false,
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq(<<-EOS)
key1 key2 val1
---- ---- ----
foo  aaa  1   
bar  bbb  2   
baz  ccc  3   
    EOS
  end

  it "generates text (space) without headers" do
    options = {
      headers: false,
      print0: false,
      print1: false,
      print2: true,
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq("foo aaa 1 bar bbb 2 baz ccc 3\n")
  end

  it "generates text (space) with headers" do
    options = {
      headers: true,
      fields: ["key1", "key2", "val1"],
      print0: false,
      print1: false,
      print2: true,
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq("foo aaa 1 bar bbb 2 baz ccc 3\n")
  end
end
