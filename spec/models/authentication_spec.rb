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

RSpec.describe Authentication, type: :model do
  describe "verification state" do
    let(:auth) { build(:authentication) }

    describe "#verified?" do
      it "is true when verified_at is present" do
        auth.verified_at = Time.current
        expect(auth.verified?).to be true
      end

      it "is false when verified_at is nil" do
        auth.verified_at = nil
        expect(auth.verified?).to be false
      end
    end

    describe "#pending?" do
      it "is true when verified_at is nil and verification_token is present" do
        auth.verified_at = nil
        auth.verification_token = "tok"
        expect(auth.pending?).to be true
      end

      it "is false when verified_at is set" do
        auth.verified_at = Time.current
        auth.verification_token = "tok"
        expect(auth.pending?).to be false
      end

      it "is false when verification_token is nil" do
        auth.verified_at = nil
        auth.verification_token = nil
        expect(auth.pending?).to be false
      end
    end

    describe "#token_expired?" do
      it "is true when verification_sent_at is older than 24 hours" do
        auth.verification_sent_at = 25.hours.ago
        expect(auth.token_expired?).to be true
      end

      it "is false when within 24 hours" do
        auth.verification_sent_at = 1.hour.ago
        expect(auth.token_expired?).to be false
      end

      it "is false when verification_sent_at is nil" do
        auth.verification_sent_at = nil
        expect(auth.token_expired?).to be false
      end
    end

    describe "#generate_verification_token!" do
      let(:auth) { create(:authentication, verified_at: Time.current, verification_token: nil) }

      it "sets a new token" do
        auth.generate_verification_token!
        expect(auth.verification_token).to be_present
        expect(auth.verification_token.length).to be >= 32
      end

      it "sets verification_sent_at to now" do
        freeze_time do
          auth.generate_verification_token!
          expect(auth.verification_sent_at).to eq(Time.current)
        end
      end

      it "clears verified_at (token regeneration invalidates prior verification)" do
        auth.generate_verification_token!
        expect(auth.verified_at).to be_nil
      end
    end

    describe "#verify!" do
      let(:auth) do
        create(:authentication,
          verified_at: nil,
          verification_token: "abc123",
          verification_sent_at: 1.hour.ago)
      end

      it "sets verified_at to now" do
        freeze_time do
          auth.verify!
          expect(auth.verified_at).to eq(Time.current)
        end
      end

      it "clears verification_token" do
        auth.verify!
        expect(auth.verification_token).to be_nil
      end

      it "clears verification_sent_at" do
        auth.verify!
        expect(auth.verification_sent_at).to be_nil
      end
    end
  end

  describe "scopes" do
    let!(:verified) { create(:authentication, verified_at: Time.current, verification_token: nil) }
    let!(:pending)  { create(:authentication, verified_at: nil, verification_token: "tok", verification_sent_at: 1.hour.ago) }

    it ".verified returns rows with verified_at set" do
      expect(Authentication.verified).to include(verified)
      expect(Authentication.verified).not_to include(pending)
    end

    it ".pending returns rows with verified_at nil and token present" do
      expect(Authentication.pending).to include(pending)
      expect(Authentication.pending).not_to include(verified)
    end
  end
end
