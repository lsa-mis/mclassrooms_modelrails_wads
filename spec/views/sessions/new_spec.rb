require "rails_helper"

RSpec.describe "sessions/new", type: :view do
  before do
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:oauth, :google, :client_id).and_return("google-client-id")
    allow(Rails.application.credentials).to receive(:dig).with(:oauth, :github, :client_id).and_return("github-client-id")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OKTA_ISSUER").and_return("https://miclassrooms-test.okta.com")
  end

  context "when Rails.configuration.x.auth.sso_only is true (production posture)" do
    before { allow(Rails.configuration.x.auth).to receive(:sso_only).and_return(true) }

    it "shows the Google sign-in button" do
      render
      expect(rendered).to have_css("form[action='/auth/google_oauth2']", text: I18n.t("oauth.sign_in_with", provider: "Google"))
    end

    it "shows the Okta sign-in button" do
      render
      expect(rendered).to have_css("form[action='/auth/okta']", text: I18n.t("oauth.sign_in_with", provider: "Okta"))
    end

    it "does NOT show the GitHub sign-in button, even though its strategy is configured" do
      render
      expect(rendered).not_to have_css("form[action='/auth/github']")
      expect(rendered).not_to have_text(I18n.t("oauth.sign_in_with", provider: "GitHub"))
    end

    it "does NOT render the email/password/magic-link lookup form" do
      render
      expect(rendered).not_to have_css("form[action='/session/lookup']")
    end

    it "does NOT render the passkey prompt" do
      render
      expect(rendered).not_to have_text(I18n.t("sessions.new.passkey_button"))
    end
  end

  context "when Rails.configuration.x.auth.sso_only is false (dev-config posture)" do
    before { allow(Rails.configuration.x.auth).to receive(:sso_only).and_return(false) }

    it "renders the email/password/magic-link lookup form" do
      render
      expect(rendered).to have_css("form[action='/session/lookup']")
    end

    it "renders the passkey prompt" do
      render
      expect(rendered).to have_text(I18n.t("sessions.new.passkey_button"))
    end

    it "still shows the OAuth buttons" do
      render
      expect(rendered).to have_css("form[action='/auth/google_oauth2']")
      expect(rendered).to have_css("form[action='/auth/okta']")
    end
  end
end
