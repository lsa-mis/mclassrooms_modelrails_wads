require "rails_helper"

RSpec.describe MagicLinkToken, type: :model do
  describe ".create_for_email" do
    it "creates a token record" do
      token = MagicLinkToken.create_for_email("test@example.com")
      expect(token).to be_present
      expect(MagicLinkToken.find_by(token: token).email).to eq("test@example.com")
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
end
