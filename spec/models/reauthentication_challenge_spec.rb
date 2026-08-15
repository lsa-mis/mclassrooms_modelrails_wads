require "rails_helper"

RSpec.describe ReauthenticationChallenge, type: :model do
  let(:user) { create(:user) }

  describe ".issue_for / .consume" do
    it "consumes a valid code exactly once" do
      code = described_class.issue_for(user)
      expect(described_class.consume(user: user, code: code)).to be(true)
      expect(described_class.consume(user: user, code: code)).to be(false)
    end

    it "rejects a wrong code without consuming the challenge" do
      code = described_class.issue_for(user)
      expect(described_class.consume(user: user, code: "000000")).to be(false)
      expect(described_class.consume(user: user, code: code)).to be(true)
    end

    it "rejects an expired code" do
      code = described_class.issue_for(user)
      described_class.where(user: user).update_all(expires_at: 1.second.ago)
      expect(described_class.consume(user: user, code: code)).to be(false)
    end

    it "is bound to the issuing user" do
      code = described_class.issue_for(user)
      other = create(:user)
      expect(described_class.consume(user: other, code: code)).to be(false)
    end

    it "supersedes a prior unconsumed challenge" do
      old_code = described_class.issue_for(user)
      described_class.issue_for(user)
      expect(described_class.consume(user: user, code: old_code)).to be(false)
    end

    it "stores only a digest, never the plaintext code" do
      code = described_class.issue_for(user)
      expect(described_class.where(user: user).pluck(:code_digest)).not_to include(code)
    end
  end
end
