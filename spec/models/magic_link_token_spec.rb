require "rails_helper"

RSpec.describe MagicLinkToken, type: :model do
  describe ".create_for_email" do
    it "creates a token record" do
      token = MagicLinkToken.create_for_email("test@example.com")
      expect(token).to be_present
      expect(MagicLinkToken.find_by(token: token).email).to eq("test@example.com")
    end

    it "supersedes prior unconsumed tokens for the same email" do
      first = MagicLinkToken.create_for_email("test@example.com")
      second = MagicLinkToken.create_for_email("test@example.com")

      expect(first).not_to eq(second)
      expect(MagicLinkToken.find_valid(first)).to be_nil
      expect(MagicLinkToken.find_valid(second)).to be_present
    end

    it "leaves at most one unconsumed token per email regardless of call count" do
      3.times { MagicLinkToken.create_for_email("test@example.com") }

      unconsumed = MagicLinkToken.where(email: "test@example.com", consumed_at: nil).count
      expect(unconsumed).to eq(1)
    end

    it "leaves other emails' unconsumed tokens untouched" do
      alice_first = MagicLinkToken.create_for_email("alice@example.com")
      bob = MagicLinkToken.create_for_email("bob@example.com")
      MagicLinkToken.create_for_email("alice@example.com")

      expect(MagicLinkToken.find_valid(alice_first)).to be_nil
      expect(MagicLinkToken.find_valid(bob)).to be_present
    end
  end

  describe ".create_for_email with intent" do
    it "persists a server-side intent on the issued token" do
      token = MagicLinkToken.create_for_email("a@example.com", intent: "set_password")
      expect(MagicLinkToken.find_by(token: token).intent).to eq("set_password")
    end

    it "defaults intent to nil for ordinary sign-in/registration links" do
      token = MagicLinkToken.create_for_email("b@example.com")
      expect(MagicLinkToken.find_by(token: token).intent).to be_nil
    end
  end

  describe ".find_valid" do
    it "finds a non-expired token" do
      token_value = MagicLinkToken.create_for_email("test@example.com")
      record = MagicLinkToken.find_valid(token_value)
      expect(record).to be_present
      expect(record.email).to eq("test@example.com")
    end

    it "returns nil for expired tokens" do
      token_value = MagicLinkToken.create_for_email("test@example.com")
      MagicLinkToken.find_by(token: token_value).update!(expires_at: 1.hour.ago)
      expect(MagicLinkToken.find_valid(token_value)).to be_nil
    end

    it "returns nil for consumed tokens" do
      token_value = MagicLinkToken.create_for_email("test@example.com")
      MagicLinkToken.find_by(token: token_value).consume!
      expect(MagicLinkToken.find_valid(token_value)).to be_nil
    end
  end

  describe "#consume! (instance)" do
    it "returns true on first call and false on subsequent calls" do
      token_value = MagicLinkToken.create_for_email("test@example.com")
      record = MagicLinkToken.find_by(token: token_value)

      expect(record.consume!).to be true
      expect(record.consume!).to be false
    end

    # Reproduces the panel-flagged race: two callers both observed
    # consumed_at: nil before either committed. Without atomic CAS, both
    # update!s succeed (no WHERE clause) and the token is double-spent.
    it "atomically detects double-consume across stale references" do
      token_value = MagicLinkToken.create_for_email("test@example.com")
      ref_a = MagicLinkToken.find_by(token: token_value)
      ref_b = MagicLinkToken.find_by(token: token_value)

      expect(ref_a.consume!).to be true
      expect(ref_b.consume!).to be false
    end

    it "reloads the record so consumed_at reflects the database after success" do
      token_value = MagicLinkToken.create_for_email("test@example.com")
      record = MagicLinkToken.find_by(token: token_value)

      record.consume!

      expect(record.consumed_at).to be_present
    end
  end

  describe ".consume!(token)" do
    it "returns the record on first call" do
      token_value = MagicLinkToken.create_for_email("test@example.com")
      result = MagicLinkToken.consume!(token_value)

      expect(result).to be_a(MagicLinkToken)
      expect(result.consumed_at).to be_present
    end

    it "returns nil on the second call (no double-spend)" do
      token_value = MagicLinkToken.create_for_email("test@example.com")
      MagicLinkToken.consume!(token_value)

      expect(MagicLinkToken.consume!(token_value)).to be_nil
    end

    it "returns nil for unknown tokens" do
      expect(MagicLinkToken.consume!("nonexistent")).to be_nil
    end

    it "returns nil for expired tokens" do
      token_value = MagicLinkToken.create_for_email("test@example.com")
      MagicLinkToken.find_by(token: token_value).update!(expires_at: 1.hour.ago)

      expect(MagicLinkToken.consume!(token_value)).to be_nil
    end
  end
end
