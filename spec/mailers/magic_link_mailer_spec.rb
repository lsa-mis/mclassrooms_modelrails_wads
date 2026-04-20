require "rails_helper"

RSpec.describe MagicLinkMailer, type: :mailer do
  describe "#sign_in_link" do
    let(:user) { create(:user) }
    let(:token) { MagicLinkToken.create_for_email(user.email_address) }

    it "sends to the user's email" do
      mail = described_class.sign_in_link(user.email_address, token)
      expect(mail.to).to eq([ user.email_address ])
    end

    it "includes the magic link token in the body" do
      mail = described_class.sign_in_link(user.email_address, token)
      expect(mail.body.encoded).to include(token)
    end

    it "has a subject" do
      mail = described_class.sign_in_link(user.email_address, token)
      expect(mail.subject).to be_present
    end
  end

  describe "#registration_link" do
    let(:token) { MagicLinkToken.create_for_email("newuser@example.com") }

    it "sends to the provided email" do
      mail = described_class.registration_link("newuser@example.com", token)
      expect(mail.to).to eq([ "newuser@example.com" ])
    end

    it "includes the registration token in the body" do
      mail = described_class.registration_link("newuser@example.com", token)
      expect(mail.body.encoded).to include(token)
    end

    it "has a subject" do
      mail = described_class.registration_link("newuser@example.com", token)
      expect(mail.subject).to be_present
    end
  end
end
