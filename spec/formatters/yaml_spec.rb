require "spec_helper"
require "hotdog/formatters"
require "hotdog/formatters/yaml"

describe "yaml" do
  let(:fmt) {
    Hotdog::Formatters::Yaml.new
  }

  it "generates yaml without headers" do
    options = {
      headers: false,
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq(<<-EOS)
---
- - foo
  - aaa
  - 1
- - bar
  - bbb
  - 2
- - baz
  - ccc
  - 3
    EOS
  end

  it "generates yaml with headers" do
    options = {
      headers: true,
      fields: ["key1", "key2", "val1"],
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq(<<-EOS)
---
- - key1
  - key2
  - val1
- - foo
  - aaa
  - 1
- - bar
  - bbb
  - 2
- - baz
  - ccc
  - 3
    EOS
  end
end
