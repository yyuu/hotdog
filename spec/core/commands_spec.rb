require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/search"

describe "commands" do
  let(:cmd) {
    Hotdog::Commands::Search.new(Hotdog::Application.new)
  }

  before(:each) do
    ENV["DATADOG_API_KEY"] = "DATADOG_API_KEY"
    ENV["DATADOG_APPLICATION_KEY"] = "DATADOG_APPLICATION_KEY"
  end

  it "get empty hosts" do
    cmd.options[:listing] = false
    cmd.options[:primary_tag] = nil
    allow(cmd).to receive(:update_db)
    expect(cmd.__send__(:get_hosts, [], [])).to eq([[], []])
  end

  it "get hosts" do
    cmd.options[:listing] = false
    cmd.options[:primary_tag] = nil
    allow(cmd).to receive(:update_db)
    allow(cmd).to receive(:get_hosts_fields).with([1, 2, 3], ["host"])
    expect(cmd.__send__(:get_hosts, [1, 2, 3], []))
  end

  it "get hosts with primary tag" do
    cmd.options[:listing] = false
    cmd.options[:primary_tag] = "foo"
    allow(cmd).to receive(:update_db)
    allow(cmd).to receive(:get_hosts_fields).with([1, 2, 3], ["foo"])
    expect(cmd.__send__(:get_hosts, [1, 2, 3], []))
  end

  it "get hosts with tags" do
    cmd.options[:listing] = false
    cmd.options[:primary_tag] = nil
    allow(cmd).to receive(:update_db)
    allow(cmd).to receive(:get_hosts_fields).with([1, 2, 3], ["foo", "bar", "baz"])
    expect(cmd.__send__(:get_hosts, [1, 2, 3], ["foo", "bar", "baz"]))
  end

  it "get hosts with all tags" do
    cmd.options[:listing] = true
    cmd.options[:primary_tag] = nil
    allow(cmd).to receive(:update_db)
    q1 = [
      "SELECT DISTINCT tags.name FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts_tags.host_id IN (?, ?, ?);",
    ]
    allow(cmd).to receive(:execute).with(q1.join(" "), [1, 2, 3]) {
      [["foo"], ["bar"], ["baz"]]
    }
    allow(cmd).to receive(:get_hosts_fields).with([1, 2, 3], ["host", "foo", "bar", "baz"])
    expect(cmd.__send__(:get_hosts, [1, 2, 3], []))
  end

  it "get hosts with all tags with primary tag" do
    cmd.options[:listing] = true
    cmd.options[:primary_tag] = "bar"
    allow(cmd).to receive(:update_db)
    q1 = [
      "SELECT DISTINCT tags.name FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts_tags.host_id IN (?, ?, ?);",
    ]
    allow(cmd).to receive(:execute).with(q1.join(" "), [1, 2, 3]) {
      [["foo"], ["bar"], ["baz"]]
    }
    allow(cmd).to receive(:get_hosts_fields).with([1, 2, 3], ["bar", "host", "foo", "baz"])
    expect(cmd.__send__(:get_hosts, [1, 2, 3], []))
  end

  it "get empty host fields" do
    expect(cmd.__send__(:get_hosts_fields, [1, 2, 3], [])).to eq([[], []])
  end

  it "get host fields without host" do
    q1 = [
      "SELECT LOWER(tags.name), GROUP_CONCAT(tags.value, ',') FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts_tags.host_id = ? AND tags.name IN (?, ?, ?)",
            "GROUP BY tags.name;",
    ]
    allow(cmd).to receive(:execute).with(q1.join(" "), [1, "foo", "bar", "baz"]) {
      [["foo", "foo1"], ["bar", "bar1"], ["baz", "baz1"]]
    }
    allow(cmd).to receive(:execute).with(q1.join(" "), [2, "foo", "bar", "baz"]) {
      [["foo", "foo2"], ["bar", "bar2"], ["baz", "baz2"]]
    }
    allow(cmd).to receive(:execute).with(q1.join(" "), [3, "foo", "bar", "baz"]) {
      [["foo", "foo3"], ["bar", "bar3"], ["baz", "baz3"]]
    }
    expect(cmd.__send__(:get_hosts_fields, [1, 2, 3], ["foo", "bar", "baz"])).to eq([[["foo1", "bar1", "baz1"], ["foo2", "bar2", "baz2"], ["foo3", "bar3", "baz3"]], ["foo", "bar", "baz"]])
  end

  it "get host fields with host" do
    q1 = [
      "SELECT LOWER(tags.name), GROUP_CONCAT(tags.value, ',') FROM hosts_tags",
        "INNER JOIN tags ON hosts_tags.tag_id = tags.id",
          "WHERE hosts_tags.host_id = ? AND tags.name IN (?, ?, ?)",
            "GROUP BY tags.name;",
    ]
    allow(cmd).to receive(:execute).with(q1.join(" "), [1, "foo", "bar", "host"]) {
      [["foo", "foo1"], ["bar", "bar1"], ["host", "host1"]]
    }
    allow(cmd).to receive(:execute).with(q1.join(" "), [2, "foo", "bar", "host"]) {
      [["foo", "foo2"], ["bar", "bar2"], ["host", "host2"]]
    }
    allow(cmd).to receive(:execute).with(q1.join(" "), [3, "foo", "bar", "host"]) {
      [["foo", "foo3"], ["bar", "bar3"], ["host", "host3"]]
    }
    expect(cmd.__send__(:get_hosts_fields, [1, 2, 3], ["foo", "bar", "host"])).to eq([[["foo1", "bar1", "host1"], ["foo2", "bar2", "host2"], ["foo3", "bar3", "host3"]], ["foo", "bar", "host"]])
  end
end
