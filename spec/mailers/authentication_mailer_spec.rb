require "rails_helper"

RSpec.describe AuthenticationMailer, type: :mailer do
  describe "#verification_email" do
    let(:user) { create(:user) }
    let(:authentication) { create(:authentication, user: user) }

    before { authentication.generate_verification_token! }

    it "sends to the user's email" do
      mail = described_class.verification_email(authentication)
      expect(mail.to).to eq([ user.email_address ])
    end

    it "includes the verification link" do
      mail = described_class.verification_email(authentication)
      expect(mail.body.encoded).to include(authentication.verification_token)
    end
  end

  describe "#password_reset_email" do
    let(:user) { create(:user) }

    it "sends to the user's email" do
      mail = described_class.password_reset_email(user)
      expect(mail.to).to eq([ user.email_address ])
    end

    it "includes the reset token in the body" do
      freeze_time do
        token = user.password_reset_token
        mail = described_class.password_reset_email(user)
        expect(mail.body.encoded).to include(token)
      end
    end

    it "has a subject" do
      mail = described_class.password_reset_email(user)
      expect(mail.subject).to be_present
    end
  end
end
