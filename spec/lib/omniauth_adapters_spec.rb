require "rails_helper"

RSpec.describe OmniauthAdapters do
  describe ".normalize_provider" do
    it "maps 'google_oauth2' to the 'google' enum value" do
      expect(OmniauthAdapters.normalize_provider("google_oauth2")).to eq("google")
    end

    it "passes through 'github' unchanged" do
      expect(OmniauthAdapters.normalize_provider("github")).to eq("github")
    end

    it "passes through unknown strategy names unchanged" do
      expect(OmniauthAdapters.normalize_provider("unknown_strategy")).to eq("unknown_strategy")
    end
  end
end
