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

  describe "#link_verification_email" do
    let(:user) { create(:user, first_name: "Alice", email_address: "alice@home.com") }
    let(:auth) do
      user.authentications.create!(
        provider: "google",
        uid: "12345",
        email: "alice.work@gmail.com",
        verification_token: "abc-token-xyz",
        verification_sent_at: Time.current
      )
    end

    subject(:mail) { described_class.link_verification_email(auth) }

    it "addresses the OAuth-returned email, not the primary email" do
      expect(mail.to).to eq([ "alice.work@gmail.com" ])
    end

    it "names the provider in the subject" do
      expect(mail.subject).to include("Google")
    end

    it "names the app in the subject" do
      expect(mail.subject).to include(I18n.t("application.name"))
    end

    it "includes the verification URL with the token in the body" do
      expect(mail.body.encoded).to include("verify/abc-token-xyz")
    end

    it "addresses the user by first name" do
      expect(mail.body.encoded).to include("Alice")
    end

    it "renders both HTML and text parts" do
      expect(mail.html_part).to be_present
      expect(mail.text_part).to be_present
    end
  end
end
