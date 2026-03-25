require "rails_helper"

RSpec.describe AuthenticationMailer, type: :mailer do
  describe "#verification_email" do
    let(:user) { create(:user) }
    let(:authentication) { create(:authentication, user: user) }

    before { authentication.generate_verification_token! }

    it "sends to the user's email" do
      mail = described_class.verification_email(authentication)
      expect(mail.to).to eq([user.email_address])
    end

    it "includes the verification link" do
      mail = described_class.verification_email(authentication)
      expect(mail.body.encoded).to include(authentication.verification_token)
    end
  end
end
