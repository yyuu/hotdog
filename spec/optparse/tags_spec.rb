require "spec_helper"
require "hotdog/application"
require "hotdog/commands/tags"

describe "option parser for tags" do
  let(:app) {
    Hotdog::Application.new
  }

  let(:cmd) {
    Hotdog::Commands::Tags.new(app)
  }

  before(:each) do
    allow(app).to receive(:get_command).with("tags") {
      cmd
    }
  end

  it "can handle common options before subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      verbosity: Hotdog::VERBOSITY_INFO,
    ))
    app.main(["--verbose", "tags", "foo", "bar", "baz"])
  end

  it "can handle common options after subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      verbosity: Hotdog::VERBOSITY_INFO,
    ))
    app.main(["tags", "--verbose", "foo", "bar", "baz"])
  end
end
