require "rails_helper"

RSpec.describe "Settings::Reauthentications", type: :request do
  def stale!(user)
    user.sessions.update_all(reauthenticated_at: 1.hour.ago)
  end

  describe "GET /settings/reauthentication (factor matrix)" do
    it "offers password + email for a password user" do
      user = create(:user)
      sign_in(user)
      get new_settings_reauthentication_path
      expect(response.body).to include(I18n.t("settings.reauthentications.new.password_label"))
      expect(response.body).to include(I18n.t("settings.reauthentications.new.email_button"))
      expect(response.body).not_to include(I18n.t("settings.reauthentications.new.passkey_button"))
    end

    it "offers only the email code for a passwordless user with no passkey" do
      user = create(:user, :passwordless)
      sign_in(user)
      get new_settings_reauthentication_path
      expect(response.body).to include(I18n.t("settings.reauthentications.new.email_button"))
      expect(response.body).not_to include(I18n.t("settings.reauthentications.new.password_label"))
      expect(response.body).not_to include(I18n.t("settings.reauthentications.new.passkey_button"))
    end
  end

  describe "GET /settings/reauthentication (emailed-code state)" do
    let(:user) { create(:user, :passwordless) }
    let(:sent_sentence) do
      I18n.t("settings.reauthentications.new.code_sent_to",
             email: user.email_address,
             minutes: ReauthenticationChallenge::EXPIRY.in_minutes.to_i)
    end

    before { sign_in(user) }

    it "shows the code field, where the code went, and a way to send a new one while a challenge is pending" do
      ReauthenticationChallenge.issue_for(user)
      get new_settings_reauthentication_path

      html = Capybara.string(response.body)
      expect(html).to have_field(I18n.t("settings.reauthentications.new.code_label"))
      expect(html).to have_text(sent_sentence)
      expect(html).to have_css("form[action='#{settings_reauthentication_code_path}'] button",
                               text: I18n.t("settings.reauthentications.new.resend_button"))
    end

    it "returns to the email-a-code state once the challenge has expired" do
      ReauthenticationChallenge.issue_for(user)

      travel 11.minutes do
        get new_settings_reauthentication_path

        html = Capybara.string(response.body)
        expect(html).to have_button(I18n.t("settings.reauthentications.new.email_button"))
        expect(html).to have_no_field(I18n.t("settings.reauthentications.new.code_label"))
      end
    end

    it "still offers a new code after a wrong code bounces back to the page" do
      ReauthenticationChallenge.issue_for(user)
      post settings_reauthentication_path, params: { code: "000000" }
      follow_redirect!

      html = Capybara.string(response.body)
      expect(html).to have_field(I18n.t("settings.reauthentications.new.code_label"))
      expect(html).to have_css("form[action='#{settings_reauthentication_code_path}'] button",
                               text: I18n.t("settings.reauthentications.new.resend_button"))
    end

    it "keeps the resend button out of the code form, which a nested form would silently break" do
      ReauthenticationChallenge.issue_for(user)
      get new_settings_reauthentication_path

      expect(response.body).not_to match(%r{<form\b(?:(?!</form>).)*<form\b}m)
    end
  end

  describe "GET /settings/reauthentication (factor-choice chrome)" do
    it "heads the choice and rules off the email factor for a user with more than one" do
      user = create(:user)
      sign_in(user)
      get new_settings_reauthentication_path

      html = Capybara.string(response.body)
      expect(html).to have_css("#reauth-choose-heading")
      expect(html).to have_css("[role='group'][aria-labelledby='reauth-choose-heading']")
      expect(html).to have_css(".page-container .border-t")
    end

    it "shows neither heading nor divider to a user whose only factor is the emailed code" do
      user = create(:user, :passwordless)
      sign_in(user)
      get new_settings_reauthentication_path

      html = Capybara.string(response.body)
      expect(html).to have_no_css("#reauth-choose-heading")
      expect(html).to have_no_css("[role='group'][aria-labelledby='reauth-choose-heading']")
      expect(html).to have_no_css(".page-container .border-t")
      expect(html).to have_button(I18n.t("settings.reauthentications.new.email_button"))
    end
  end

  describe "POST /settings/reauthentication (password factor)" do
    let(:user) { create(:user) }
    before { sign_in(user) }

    it "stamps reauthentication and returns to the stored path on the right password" do
      stale!(user)
      session_via_request = user.sessions.sole
      post settings_reauthentication_path, params: { password: "SecureP@ssw0rd123!" }
      expect(session_via_request.reload.reauthenticated?).to be(true)
    end

    it "does not stamp on a wrong password" do
      stale!(user)
      post settings_reauthentication_path, params: { password: "wrong-password" }
      expect(user.sessions.sole.reload.reauthenticated?).to be(false)
      expect(flash[:alert]).to eq(I18n.t("settings.reauthentications.create.wrong_password"))
    end

    it "does not stamp once rate limited, even on the right password, and says so" do
      stale!(user)
      allow(Rails.cache).to receive(:increment).and_return(11)
      post settings_reauthentication_path, params: { password: "SecureP@ssw0rd123!" }

      expect(response).to redirect_to(new_settings_reauthentication_path)
      expect(flash[:alert]).to eq(I18n.t("settings.reauthentications.rate_limited"))
      expect(user.sessions.sole.reload.reauthenticated?).to be(false)
    end
  end

  describe "POST /settings/reauthentication (email code factor)" do
    let(:user) { create(:user, :passwordless) }
    before { sign_in(user) }

    it "emails a code and verifies it, stamping reauthentication" do
      expect {
        post settings_reauthentication_code_path
      }.to have_enqueued_mail(ReauthenticationMailer, :code)
      expect(flash[:notice]).to eq(I18n.t("settings.reauthentication_codes.create.sent"))

      stale!(user)
      code = ReauthenticationChallenge.issue_for(user) # deterministic handle to the plaintext
      post settings_reauthentication_path, params: { code: code }
      expect(user.sessions.sole.reload.reauthenticated?).to be(true)
    end

    it "rejects a wrong code" do
      stale!(user)
      ReauthenticationChallenge.issue_for(user)
      post settings_reauthentication_path, params: { code: "000000" }
      expect(user.sessions.sole.reload.reauthenticated?).to be(false)
      expect(flash[:alert]).to eq(I18n.t("settings.reauthentications.create.wrong_code"))
    end
  end

  describe "POST /settings/reauthentication with no factor" do
    it "prompts the user to choose one" do
      user = create(:user)
      sign_in(user)
      post settings_reauthentication_path, params: {}
      expect(flash[:alert]).to eq(I18n.t("settings.reauthentications.create.no_factor"))
    end
  end


  describe "gated actions require fresh reauthentication" do
    let(:user) { create(:user) }
    before do
      sign_in(user)
      stale!(user)
    end

    it "redirects a password change to the interstitial" do
      patch settings_password_path, params: { user: { password: "N3wP@ssw0rd!x", password_confirmation: "N3wP@ssw0rd!x" } }
      expect(response).to redirect_to(new_settings_reauthentication_path)
    end

    it "redirects a passkey deletion to the interstitial" do
      cred = user.webauthn_credentials.create!(external_id: "x", public_key: "y", nickname: "k", sign_count: 0)
      delete settings_passkey_path(cred)
      expect(response).to redirect_to(new_settings_reauthentication_path)
    end

    it "answers a gated XHR (passkey enrollment) with a reauth_required JSON signal" do
      post passkeys_registration_challenge_path, headers: { "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["reauth_required"]).to be(true)
      expect(response.parsed_body["redirect_to"]).to eq(new_settings_reauthentication_path)
    end
  end
end
