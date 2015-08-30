require "spec_helper"
require "hotdog/application"
require "hotdog/commands"
require "hotdog/commands/hosts"
require "hotdog/commands/search"
require "hotdog/commands/tags"

describe "application" do
  let(:app) {
    Hotdog::Application.new
  }

  before(:each) do
    ENV["DATADOG_API_KEY"] = "DATADOG_API_KEY"
    ENV["DATADOG_APPLICATION_KEY"] = "DATADOG_APPLICATION_KEY"
  end

  it "generates proper class name from file name" do
    expect(app.__send__(:const_name, "csv")).to eq("Csv")
    expect(app.__send__(:const_name, "json")).to eq("Json")
    expect(app.__send__(:const_name, "pssh")).to eq("Pssh")
    expect(app.__send__(:const_name, "parallel-ssh")).to eq("ParallelSsh")
  end

  it "returns proper class by name" do
    expect(app.__send__(:get_command, "hosts")).to be(Hotdog::Commands::Hosts)
    expect(app.__send__(:get_command, "search")).to be(Hotdog::Commands::Search)
    expect(app.__send__(:get_command, "tags")).to be(Hotdog::Commands::Tags)
  end

  it "raises error if the action is base-command" do
    expect {
      app.main(["base-command"])
    }.to raise_error(NotImplementedError)
  end
end
