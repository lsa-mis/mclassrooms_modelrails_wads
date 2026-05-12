require "rails_helper"

RSpec.describe Account::NotificationPreferencesPolicy do
  describe "for an authenticated user" do
    let(:user) { create(:user) }
    let(:preferences) { user.create_preferences! }

    it "allows edit" do
      expect(described_class.new(user, preferences).edit?).to be true
    end

    it "allows update" do
      expect(described_class.new(user, preferences).update?).to be true
    end

    it "allows dismiss_banner" do
      expect(described_class.new(user, preferences).dismiss_banner?).to be true
    end
  end

  describe "for a nil user (unauthenticated)" do
    let(:user) { nil }
    let(:preferences) { create(:user).create_preferences! }

    it "denies edit" do
      expect(described_class.new(user, preferences).edit?).to be false
    end

    it "denies update" do
      expect(described_class.new(user, preferences).update?).to be false
    end

    it "denies dismiss_banner" do
      expect(described_class.new(user, preferences).dismiss_banner?).to be false
    end
  end
end
