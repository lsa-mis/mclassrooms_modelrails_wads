require "rails_helper"

RSpec.describe Authentication, type: :model do
  describe "validations" do
    it "requires a provider" do
      auth = build(:authentication, provider: nil)
      expect(auth).not_to be_valid
    end

    it "requires a uid" do
      auth = build(:authentication, uid: nil)
      expect(auth).not_to be_valid
    end

    it "enforces unique provider per user" do
      user = create(:user)
      create(:authentication, user: user, provider: "google", uid: "123")
      duplicate = build(:authentication, user: user, provider: "google", uid: "456")
      expect(duplicate).not_to be_valid
    end

    it "allows same provider for different users" do
      create(:authentication, provider: "google", uid: "123")
      other = build(:authentication, provider: "google", uid: "456")
      expect(other).to be_valid
    end

    describe "avatar_url format" do
      it "accepts https URLs" do
        auth = build(:authentication, avatar_url: "https://example.com/avatar.png")
        expect(auth).to be_valid
      end

      it "allows blank avatar_url" do
        auth = build(:authentication, avatar_url: nil)
        expect(auth).to be_valid
      end

      it "rejects http (non-TLS) URLs" do
        auth = build(:authentication, avatar_url: "http://example.com/avatar.png")
        expect(auth).not_to be_valid
      end

      it "rejects URLs with embedded whitespace (prevents newline injection)" do
        auth = build(:authentication, avatar_url: "https://example.com\njavascript:alert(1)")
        expect(auth).not_to be_valid
      end

      it "rejects javascript: scheme" do
        auth = build(:authentication, avatar_url: "javascript:alert(1)")
        expect(auth).not_to be_valid
      end
    end
  end

  describe "providers" do
    it "supports email provider" do
      auth = build(:authentication, provider: "email")
      expect(auth.email?).to be true
    end

    it "supports google provider" do
      auth = build(:authentication, provider: "google")
      expect(auth.google?).to be true
    end

    it "supports github provider" do
      auth = build(:authentication, provider: "github")
      expect(auth.github?).to be true
    end
  end

  describe "email verification" do
    it "can generate a verification token" do
      auth = create(:authentication, provider: "email")
      auth.generate_verification_token!
      expect(auth.verification_token).to be_present
      expect(auth.verification_sent_at).to be_present
    end

    it "can verify" do
      auth = create(:authentication, provider: "email")
      auth.generate_verification_token!
      auth.verify!
      expect(auth.verified_at).to be_present
      expect(auth.verification_token).to be_nil
    end
  end

  describe "#verified?" do
    it "returns true when verified_at is present" do
      auth = create(:authentication, :verified)
      expect(auth).to be_verified
    end

    it "returns false when verified_at is nil" do
      auth = create(:authentication)
      expect(auth).not_to be_verified
    end
  end

  describe "#verification_token_expired?" do
    it "returns true when verification_sent_at is nil" do
      auth = create(:authentication)
      expect(auth.verification_token_expired?).to be true
    end

    it "returns true when sent more than 24 hours ago" do
      auth = create(:authentication)
      auth.update!(verification_sent_at: 25.hours.ago, verification_token: "test")
      expect(auth.verification_token_expired?).to be true
    end

    it "returns false when sent less than 24 hours ago" do
      auth = create(:authentication)
      auth.update!(verification_sent_at: 1.hour.ago, verification_token: "test")
      expect(auth.verification_token_expired?).to be false
    end
  end

  describe ".oauth scope" do
    it "returns only non-email providers" do
      email_auth = create(:authentication, provider: "email")
      google_auth = create(:authentication, :google)
      expect(Authentication.oauth).to include(google_auth)
      expect(Authentication.oauth).not_to include(email_auth)
    end
  end
end
