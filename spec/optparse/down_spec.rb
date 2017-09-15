require "spec_helper"
require "hotdog/application"
require "hotdog/commands/down"

describe "option parser for down" do
  let(:app) {
    Hotdog::Application.new
  }

  let(:cmd) {
    Hotdog::Commands::Down.new(app)
  }

  before(:each) do
    allow(app).to receive(:get_command).with("down") {
      cmd
    }
  end

  it "cannot handle subcommand options before subcommand" do
    expect {
      app.main(["--downtime", "86400", "down", "foo", "bar", "baz"])
    }.to raise_error(OptionParser::InvalidOption)
  end

  it "can handle subcommand options after subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      downtime: 12345,
      verbosity: Hotdog::VERBOSITY_NULL,
    ))
    app.main(["down", "--downtime", "12345", "foo", "bar", "baz"])
  end

  it "can handle common options before subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      downtime: 12345,
      verbosity: Hotdog::VERBOSITY_INFO,
    ))
    app.main(["--verbose", "down", "--downtime", "12345", "foo", "bar", "baz"])
  end

  it "can handle common options after subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      downtime: 12345,
      verbosity: Hotdog::VERBOSITY_INFO,
    ))
    app.main(["down", "--downtime", "12345", "--verbose", "foo", "bar", "baz"])
  end
end
