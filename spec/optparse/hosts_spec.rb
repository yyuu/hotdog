require "spec_helper"
require "hotdog/application"
require "hotdog/commands/hosts"

describe "option parser for hosts" do
  let(:app) {
    Hotdog::Application.new
  }

  let(:cmd) {
    Hotdog::Commands::Hosts.new(app)
  }

  before(:each) do
    allow(app).to receive(:get_command).with("hosts") {
      cmd
    }
  end

  it "can handle common options before subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      verbose: true,
    ))
    app.main(["--verbose", "hosts", "foo", "bar", "baz"])
  end

  it "can handle common options after subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      verbose: true,
    ))
    app.main(["hosts", "--verbose", "foo", "bar", "baz"])
  end
end
