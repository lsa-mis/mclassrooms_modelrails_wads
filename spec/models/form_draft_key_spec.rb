require "rails_helper"

RSpec.describe FormDraftKey do
  let(:user)  { create(:user) }
  let(:other) { create(:user) }

  describe ".for" do
    it "derives a stable 32-byte key per user" do
      expect(described_class.for(user).bytesize).to eq(32)
      expect(described_class.for(user)).to eq(described_class.for(user))
    end

    it "derives different keys for different users" do
      expect(described_class.for(user)).not_to eq(described_class.for(other))
    end

    it "uses the Rails key generator (participates in secret rotation)" do
      expect(Rails.application.key_generator)
        .to receive(:generate_key).with("form-draft:#{user.id}", 32).and_call_original
      described_class.for(user)
    end
  end

  describe ".scope_for" do
    it "returns a short stable hex digest, distinct per user" do
      expect(described_class.scope_for(user)).to match(/\A\h{8}\z/)
      expect(described_class.scope_for(user)).to eq(described_class.scope_for(user))
      expect(described_class.scope_for(user)).not_to eq(described_class.scope_for(other))
    end

    it "is domain-separated from the key (HMAC, not a bare hash)" do
      expect(described_class.scope_for(user))
        .to eq(OpenSSL::HMAC.hexdigest("SHA256", described_class.for(user), "form-draft-scope").first(8))
    end
  end
end
