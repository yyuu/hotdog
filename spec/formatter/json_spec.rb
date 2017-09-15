require "spec_helper"
require "hotdog/formatters"
require "hotdog/formatters/json"

describe "json" do
  let(:fmt) {
    Hotdog::Formatters::Json.new
  }

  it "generates json without headers" do
    options = {
      headers: false,
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq(<<-EOS)
[
  [
    "foo",
    "aaa",
    1
  ],
  [
    "bar",
    "bbb",
    2
  ],
  [
    "baz",
    "ccc",
    3
  ]
]
    EOS
  end

  it "generates json with headers" do
    options = {
      headers: true,
      fields: ["key1", "key2", "val1"],
      prettyprint: false,
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq(<<-EOS)
[
  {
    "key1": "foo",
    "key2": "aaa",
    "val1": 1
  },
  {
    "key1": "bar",
    "key2": "bbb",
    "val1": 2
  },
  {
    "key1": "baz",
    "key2": "ccc",
    "val1": 3
  }
]
    EOS
  end
end
