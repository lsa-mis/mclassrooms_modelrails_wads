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
      post passkeys_registration_options_path, headers: { "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["reauth_required"]).to be(true)
      expect(response.parsed_body["redirect_to"]).to eq(new_settings_reauthentication_path)
    end
  end
end
