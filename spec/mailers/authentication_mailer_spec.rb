require "rails_helper"

RSpec.describe AuthenticationMailer, type: :mailer do
  describe "#verification_email" do
    let(:user) { create(:user) }
    let(:authentication) { create(:authentication, user: user, verified_at: nil) }

    it "sends to the user's email" do
      mail = described_class.verification_email(authentication)
      expect(mail.to).to eq([ user.email_address ])
    end

    it "includes the verification link" do
      mail = described_class.verification_email(authentication)
      expect(mail.body.encoded).to include(email_verification_path)
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
        verified_at: nil
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

    it "includes the verification URL in the body" do
      expect(mail.body.encoded).to include("/connected_accounts/verify/")
    end

    it "addresses the user by first name" do
      expect(mail.body.encoded).to include("Alice")
    end

    it "renders both HTML and text parts" do
      expect(mail.html_part).to be_present
      expect(mail.text_part).to be_present
    end

    it "wraps the HTML in a <html lang='en'> element (WCAG 3.1.1)" do
      expect(mail.html_part.body.encoded).to include('<html lang="en">')
    end

    it "includes a preheader snippet for inbox preview" do
      # Preheader text appears in inbox previews. Should be a hidden span
      # near the top of the body containing a useful preview of the email.
      html = mail.html_part.body.encoded
      preheader_match = html.match(/<span[^>]*class="preheader"[^>]*>([^<]*)<\/span>/)
      expect(preheader_match).not_to be_nil, "expected a <span class='preheader'> snippet near the top of the body"
      expect(preheader_match[1].strip).to be_present
    end

    it "renders exactly one <html> element (layout-wrapped, not nested)" do
      expect(mail.html_part.body.encoded.scan(/<html[^>]*>/i).length).to eq(1)
    end
  end

  describe "#collision_alert" do
    let(:legitimate_user) { create(:user, first_name: "Alice", email_address: "alice@example.com") }

    subject(:mail) { described_class.collision_alert(legitimate_user, "Google") }

    it "addresses the legitimate owner of the OAuth identity" do
      expect(mail.to).to eq([ "alice@example.com" ])
    end

    it "names the provider in the subject" do
      expect(mail.subject).to include("Google")
    end

    it "names the app in the subject" do
      expect(mail.subject).to include(I18n.t("application.name"))
    end

    it "addresses the user by first name" do
      expect(mail.body.encoded).to include("Alice")
    end

    it "links to the connected accounts page" do
      expect(mail.body.encoded).to include("/settings/connected_accounts")
    end

    it "renders both HTML and text parts" do
      expect(mail.html_part).to be_present
      expect(mail.text_part).to be_present
    end

    it "wraps the HTML in a <html lang='en'> element (WCAG 3.1.1)" do
      expect(mail.html_part.body.encoded).to include('<html lang="en">')
    end

    it "states the user's account is unaffected (defense-in-depth, not breach notice)" do
      expect(mail.body.encoded.downcase).to include("blocked")
    end
  end
end
