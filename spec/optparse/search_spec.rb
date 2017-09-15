require "spec_helper"
require "hotdog/application"
require "hotdog/commands/search"

describe "option parser for search" do
  let(:app) {
    Hotdog::Application.new
  }

  let(:cmd) {
    Hotdog::Commands::Search.new(app)
  }

  before(:each) do
    allow(app).to receive(:get_command).with("search") {
      cmd
    }
  end

  it "can handle common options before subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      verbosity: Hotdog::VERBOSITY_INFO,
    ))
    app.main(["--verbose", "search", "foo", "bar", "baz"])
  end

  it "can handle common options after subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      verbosity: Hotdog::VERBOSITY_INFO,
    ))
    app.main(["search", "--verbose", "foo", "bar", "baz"])
  end
end
