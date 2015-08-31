require "spec_helper"
require "hotdog/formatters"
require "hotdog/formatters/ltsv"

describe "ltsv" do
  let(:fmt) {
    Hotdog::Formatters::Ltsv.new
  }

  it "generates ltsv without headers" do
    options = {
      headers: false,
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq(<<-EOS)
foo\taaa\t1
bar\tbbb\t2
baz\tccc\t3
    EOS
  end

  it "generates ltsv with headers" do
    options = {
      headers: true,
      fields: ["key1", "key2", "val1"],
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq(<<-EOS)
key1:foo\tkey2:aaa\tval1:1
key1:bar\tkey2:bbb\tval1:2
key1:baz\tkey2:ccc\tval1:3
    EOS
  end
end
