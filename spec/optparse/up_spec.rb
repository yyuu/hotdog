require "spec_helper"
require "hotdog/application"
require "hotdog/commands/up"

describe "option parser for up" do
  let(:app) {
    Hotdog::Application.new
  }

  let(:cmd) {
    Hotdog::Commands::Up.new(app)
  }

  before(:each) do
    allow(app).to receive(:get_command).with("up") {
      cmd
    }
  end

  it "can handle common options before subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      verbosity: Hotdog::VERBOSITY_INFO,
    ))
    app.main(["--verbose", "up", "foo", "bar", "baz"])
  end

  it "can handle common options after subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      verbosity: Hotdog::VERBOSITY_INFO,
    ))
    app.main(["up", "--verbose", "foo", "bar", "baz"])
  end
end
