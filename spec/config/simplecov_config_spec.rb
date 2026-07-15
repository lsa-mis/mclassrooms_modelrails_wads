require "rails_helper"

RSpec.describe "SimpleCov configuration" do
  it "is running for this process" do
    expect(SimpleCov.running).to be_truthy
  end

  it "tags results with a per-worker command name so parallel resultsets merge" do
    expect(SimpleCov.command_name).to eq("rspec#{ENV['TEST_ENV_NUMBER']}")
  end
end
