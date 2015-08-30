require "spec_helper"
require "hotdog/formatters"
require "hotdog/formatters/csv"

describe "csv" do
  let(:fmt) {
    Hotdog::Formatters::Csv.new
  }

  it "generates csv without headers" do
    options = {
      headers: false,
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq(<<-EOS)
foo,aaa,1
bar,bbb,2
baz,ccc,3
    EOS
  end

  it "generates csv with headers" do
    options = {
      headers: true,
      fields: ["key1", "key2", "val1"],
    }
    expect(fmt.format([["foo", "aaa", 1], ["bar", "bbb", 2], ["baz", "ccc", 3]], options)).to eq(<<-EOS)
key1,key2,val1
foo,aaa,1
bar,bbb,2
baz,ccc,3
    EOS
  end
end
