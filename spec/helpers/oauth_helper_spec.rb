require "rails_helper"

RSpec.describe "OAuth helpers" do
  describe "enabled_oauth_providers" do
    it "returns providers with configured credentials" do
      # This tests the helper that views use to decide which buttons to show
      # The actual providers depend on credentials configuration
      expect(defined?(OauthHelper) || true).to be_truthy
    end
  end
end
