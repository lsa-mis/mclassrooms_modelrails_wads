require "rails_helper"

RSpec.describe "User magic link methods", type: :model do
  let(:user) { create(:user) }

  describe "#generate_magic_link_token!" do
    it "sets magic_link_token and magic_link_sent_at" do
      user.generate_magic_link_token!
      expect(user.magic_link_token).to be_present
      expect(user.magic_link_sent_at).to be_present
    end
  end

  describe "#magic_link_token_valid?" do
    it "returns true for fresh tokens" do
      user.generate_magic_link_token!
      expect(user.magic_link_token_valid?).to be true
    end

    it "returns false after 15 minutes" do
      user.generate_magic_link_token!
      user.update_column(:magic_link_sent_at, 16.minutes.ago)
      expect(user.magic_link_token_valid?).to be false
    end

    it "returns false when token is nil" do
      expect(user.magic_link_token_valid?).to be false
    end
  end

  describe "#clear_magic_link_token!" do
    it "clears the token" do
      user.generate_magic_link_token!
      user.clear_magic_link_token!
      expect(user.magic_link_token).to be_nil
    end
  end

  describe "#has_password?" do
    it "returns true when password_digest is present" do
      expect(user.has_password?).to be true
    end

    it "returns false when password_digest is nil" do
      user.update_column(:password_digest, nil)
      expect(user.has_password?).to be false
    end
  end
end
