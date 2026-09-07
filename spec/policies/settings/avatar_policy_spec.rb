require "rails_helper"

RSpec.describe Settings::AvatarPolicy do
  describe "for an authenticated user" do
    let(:user) { create(:user) }

    it "allows update" do
      expect(described_class.new(user, user).update?).to be true
    end

    it "allows show (the picker hub)" do
      expect(described_class.new(user, user).show?).to be true
    end
  end

  describe "for a nil user (unauthenticated)" do
    let(:user) { nil }

    it "denies update" do
      expect(described_class.new(user, user).update?).to be false
    end

    it "denies show" do
      expect(described_class.new(user, user).show?).to be false
    end
  end
end
