require "rails_helper"

RSpec.describe "SimpleCov configuration" do
  # Asserts the outcome — the Ruby VM is actually collecting coverage — rather
  # than a SimpleCov flag. `SimpleCov.running` carried this until it was
  # removed in SimpleCov 1.0; `Coverage.running?` is stdlib, is what SimpleCov
  # itself checks before starting, and cannot be satisfied by a config object
  # that got built without instrumentation ever turning on.
  it "is collecting coverage for this process" do
    require "coverage"
    expect(Coverage.running?).to be(true)
  end

  it "tags results with a per-worker command name so parallel resultsets merge" do
    expect(SimpleCov.command_name).to eq("rspec#{ENV['TEST_ENV_NUMBER']}")
  end
end
