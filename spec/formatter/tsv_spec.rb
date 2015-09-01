require "spec_helper"
require "hotdog/formatters"
require "hotdog/formatters/tsv"

describe "tsv" do
  let(:fmt) {
    Hotdog::Formatters::Tsv.new
  }

  it "generates tsv without headers" do
    options = {
      headers: false,
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq(<<-EOS)
foo\taaa\t1
bar\tbbb\t2
baz\tccc\t3
    EOS
  end

  it "generates tsv with headers" do
    options = {
      headers: true,
      fields: ["key1", "key2", "val1"],
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq(<<-EOS)
key1\tkey2\tval1
foo\taaa\t1
bar\tbbb\t2
baz\tccc\t3
    EOS
  end
end
