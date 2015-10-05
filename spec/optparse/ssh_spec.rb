require "spec_helper"
require "hotdog/application"
require "hotdog/commands/ssh"

describe "option parser for ssh" do
  let(:app) {
    Hotdog::Application.new
  }

  let(:cmd) {
    Hotdog::Commands::Ssh.new(app)
  }

  before(:each) do
    allow(app).to receive(:get_command).with("ssh") {
      cmd
    }
  end

  it "cannot handle subcommand options before subcommand" do
    expect {
      app.main(["--index", "42", "ssh", "foo", "bar", "baz"])
    }.to raise_error(OptionParser::InvalidOption)
  end

  it "can handle subcommand options after subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      index: 42,
      verbose: false,
    ))
    app.main(["ssh", "--index", "42", "foo", "bar", "baz"])
  end

  it "can handle common options before subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      index: 42,
      verbose: true,
    ))
    app.main(["--verbose", "ssh", "--index", "42", "foo", "bar", "baz"])
  end

  it "can handle common options after subcommand" do
    allow(cmd).to receive(:run).with(["foo", "bar", "baz"], a_hash_including(
      index: 42,
      verbose: true,
    ))
    app.main(["ssh", "--index", "42", "--verbose", "foo", "bar", "baz"])
  end

  it "can handle subcommand options with remote command, 1" do
    allow(cmd).to receive(:run).with([], a_hash_including(
      index: 42,
      verbose: true,
    ))
    app.main(["ssh", "--index", "42", "--verbose", "--", "foo", "bar", "baz"])
    expect(cmd.remote_command).to eq("foo bar baz")
  end

  it "can handle subcommand options with remote command, 2" do
    allow(cmd).to receive(:run).with(["foo"], a_hash_including(
      index: 42,
      verbose: true,
    ))
    app.main(["ssh", "--index", "42", "--verbose", "foo", "--", "bar", "baz"])
    expect(cmd.remote_command).to eq("bar baz")
  end

  it "can handle subcommand options with remote command, 3" do
    allow(cmd).to receive(:run).with(["foo"], a_hash_including(
      index: 42,
      verbose: true,
    ))
    app.main(["ssh", "--index", "42", "--verbose", "foo", "--", "bar", "--", "baz"])
    expect(cmd.remote_command).to eq("bar -- baz")
  end
end
