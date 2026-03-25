require "rails_helper"

RSpec.describe UserPreferences, type: :model do
  describe "validations" do
    it "allows valid themes" do
      prefs = build(:user_preferences, theme: "light")
      expect(prefs).to be_valid
    end

    it "rejects invalid themes" do
      expect {
        build(:user_preferences, theme: "neon")
      }.to raise_error(ArgumentError)
    end
  end

  describe "theme" do
    it "defaults to system" do
      prefs = UserPreferences.new
      expect(prefs.theme).to eq("system")
    end
  end
end
