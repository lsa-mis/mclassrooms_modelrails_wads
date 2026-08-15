require "rails_helper"

# Extracted from user_spec.rb when the email-change state machine moved off
# User (DES-1). Behavior is unchanged; only the call surface differs.
RSpec.describe Users::EmailChange, type: :model do
  describe "#initiate!" do
    let(:user) { create(:user) }

    it "sets pending fields" do
      result = described_class.new(user).initiate!("new@example.com")
      expect(result).to be true
      expect(user.reload.pending_email).to eq("new@example.com")
      expect(user.pending_email_token).to be_present
      expect(user.pending_email_sent_at).to be_present
    end

    it "returns false when email format is invalid" do
      result = described_class.new(user).initiate!("notanemail")
      expect(result).to be false
      expect(user.reload.pending_email).to be_nil
    end

    it "returns false when email is already taken" do
      create(:user, email_address: "taken@example.com")
      result = described_class.new(user).initiate!("taken@example.com")
      expect(result).to be false
      expect(user.reload.pending_email).to be_nil
    end

    it "returns false when email is same as current" do
      result = described_class.new(user).initiate!(user.email_address)
      expect(result).to be false
    end

    it "overwrites previous pending change" do
      described_class.new(user).initiate!("first@example.com")
      described_class.new(user).initiate!("second@example.com")
      expect(user.reload.pending_email).to eq("second@example.com")
    end

    it "works for a passwordless user (SEC-2b: no password required)" do
      oauth_user = create(:user, password: nil, password_digest: nil)
      result = described_class.new(oauth_user).initiate!("new@example.com")
      expect(result).to be true
      expect(oauth_user.reload.pending_email).to eq("new@example.com")
    end

    it "normalizes the pending email" do
      described_class.new(user).initiate!("  NEW@EXAMPLE.COM  ")
      expect(user.reload.pending_email).to eq("new@example.com")
    end
  end

  describe "#confirm!" do
    let(:user) { create(:user, :with_email_auth) }

    before do
      described_class.new(user).initiate!("new@example.com")
      user.reload
    end

    it "updates email_address with valid token" do
      token = user.pending_email_token
      result = described_class.new(user).confirm!(token)
      expect(result).to be true
      expect(user.reload.email_address).to eq("new@example.com")
    end

    it "updates email Authentication uid" do
      email_auth = user.authentications.email.first
      token = user.pending_email_token
      described_class.new(user).confirm!(token)
      expect(email_auth.reload.uid).to eq("new@example.com")
    end

    it "does not touch OAuth authentications" do
      oauth_auth = user.authentications.create!(provider: "google", uid: "google123", verified_at: Time.current)
      token = user.pending_email_token
      described_class.new(user).confirm!(token)
      expect(oauth_auth.reload.uid).to eq("google123")
    end

    it "clears pending fields" do
      token = user.pending_email_token
      described_class.new(user).confirm!(token)
      user.reload
      expect(user.pending_email).to be_nil
      expect(user.pending_email_token).to be_nil
      expect(user.pending_email_sent_at).to be_nil
    end

    it "returns false for expired token" do
      user.update!(pending_email_sent_at: 25.hours.ago)
      result = described_class.new(user).confirm!(user.pending_email_token)
      expect(result).to be false
      expect(user.reload.email_address).not_to eq("new@example.com")
    end

    it "returns false for wrong token" do
      result = described_class.new(user).confirm!("wrong-token")
      expect(result).to be false
    end

    it "returns false for nil token" do
      result = described_class.new(user).confirm!(nil)
      expect(result).to be false
    end
  end

  describe "#cancel!" do
    let(:user) { create(:user) }

    it "clears all pending fields" do
      described_class.new(user).initiate!("new@example.com")
      described_class.new(user).cancel!
      user.reload
      expect(user.pending_email).to be_nil
      expect(user.pending_email_token).to be_nil
      expect(user.pending_email_sent_at).to be_nil
    end
  end

  describe "#valid_token?" do
    let(:user) { create(:user) }

    it "returns true for fresh token" do
      described_class.new(user).initiate!("new@example.com")
      expect(described_class.new(user).valid_token?).to be true
    end

    it "returns false for expired token" do
      described_class.new(user).initiate!("new@example.com")
      user.update!(pending_email_sent_at: 25.hours.ago)
      expect(described_class.new(user).valid_token?).to be false
    end

    it "returns false when no token" do
      expect(described_class.new(user).valid_token?).to be false
    end
  end
end
