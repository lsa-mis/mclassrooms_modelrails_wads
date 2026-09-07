require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:user) { create(:user) }

  describe "GET /session/new" do
    it "renders the sign in form" do
      get new_session_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the passkey sign-in elements" do
      get new_session_path
      doc = Nokogiri::HTML(response.body)

      # Stimulus controller wrapper
      expect(doc.at_css("[data-controller~='webauthn']")).to be_present

      # Passkey button with localized label
      button = doc.at_css("[data-action='webauthn#authenticate']")
      expect(button).to be_present
      expect(button.text.strip).to include(I18n.t("sessions.new.passkey_button"))

      # Email field autocomplete for conditional UI
      email = doc.at_css("input[autocomplete~='webauthn']")
      expect(email).to be_present

      # ARIA live region for status announcements
      status = doc.at_css("[role='status'][aria-live='polite']")
      expect(status).to be_present
    end

    it "leads with the email field; the passkey is a secondary fallback below it" do
      get new_session_path
      doc = Nokogiri::HTML(response.body)

      # Both selectors resolve in DOCUMENT order, so the first node is whichever
      # the visitor meets first. Email-first posture: the email input precedes
      # the explicit passkey control (which is now a secondary link, not a
      # prominent button competing with the field).
      ordered = doc.css("input[autocomplete~='webauthn'], [data-action='webauthn#authenticate']")
      expect(ordered.size).to eq(2)
      expect(ordered.first.name).to eq("input")
    end

    context "when the visitor is already signed in" do
      it "redirects to root with an already-signed-in notice" do
        sign_in(user)
        get new_session_path
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq(I18n.t("authentication.already_signed_in"))
      end
    end

    context "with oauth providers enabled" do
      before do
        # oauth_enabled? gates the button rendering. enabled_oauth_providers filters
        # PROVIDER_CONFIG by which providers have a client_id in credentials
        # (OauthHelper#enabled_oauth_providers). Stub the SOURCE so the real helper
        # computes: google present -> the Google button renders (spec/system/invite_only_signup_spec.rb's pattern).
        allow(Rails.application.credentials).to receive(:dig).and_call_original
        allow(Rails.application.credentials).to receive(:dig)
          .with(:oauth, :google, :client_id).and_return("test-google-client-id")
      end

      it "renders provider buttons as secondary buttons preserving the non-Turbo form" do
        get new_session_path
        html = Capybara.string(response.body)
        expect(html).to have_css("form[data-turbo='false'] button.btn-secondary.w-full.gap-3")
      end
    end
  end

  describe "POST /session" do
    context "with valid credentials" do
      it "signs in the user" do
        post session_path, params: {
          email_address: user.email_address,
          password: "SecureP@ssw0rd123!"
        }
        expect(response).to redirect_to(root_path)
      end
    end

    context "with invalid credentials" do
      it "rejects the sign in" do
        post session_path, params: {
          email_address: user.email_address,
          password: "wrongpassword"
        }
        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "DELETE /session" do
    it "signs out the user" do
      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }
      delete session_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "POST /session with locked account" do
    let(:locked_user) { create(:user) }

    before do
      5.times { locked_user.register_failed_login! }
    end

    it "rejects sign in for locked user" do
      post session_path, params: {
        email_address: locked_user.email_address,
        password: "SecureP@ssw0rd123!"
      }
      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to include(I18n.t("sessions.create.locked"))
    end
  end

  describe "POST /session tracks failed attempts" do
    let(:user) { create(:user) }

    it "increments failed_login_attempts on bad password" do
      post session_path, params: {
        email_address: user.email_address,
        password: "wrongpassword"
      }
      expect(user.reload.failed_login_attempts).to eq(1)
    end
  end

  describe "POST /session resets attempts on success" do
    let(:user) { create(:user) }

    before do
      3.times { user.register_failed_login! }
    end

    it "resets failed_login_attempts on successful login" do
      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }
      expect(user.reload.failed_login_attempts).to eq(0)
    end
  end

  describe "POST /session with non-existent email" do
    it "redirects with failure flash" do
      post session_path, params: { email_address: "ghost@example.com", password: "anything" }
      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to be_present
    end
  end

  # The email-first lookup moved to spec/requests/sessions/lookups_spec.rb with the resource (#1007).
end
