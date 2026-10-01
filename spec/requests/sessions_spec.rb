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
        expect(flash[:notice]).to eq(I18n.t("sessions.create.success"))
      end
    end

    context "with invalid credentials" do
      # Distinguishes a wrong password from a lockout, same destination (#526).
      it "rejects the sign in" do
        post session_path, params: {
          email_address: user.email_address,
          password: "wrongpassword"
        }
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to eq(I18n.t("sessions.create.failure"))
      end
    end
  end

  # Both land on new_session_path like a wrong password (#526).
  describe "POST /session — refusals that share a destination" do
    it "says it was rate limited once the limit is exceeded" do
      # An over-limit increment fires the limiter without a persistent cache.
      allow(Rails.cache).to receive(:increment).and_return(11)

      post session_path, params: { email_address: user.email_address, password: "SecureP@ssw0rd123!" }

      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq(I18n.t("sessions.create.rate_limited"))
    end

    # Same destination as every refusal, so only the alert identifies it.
    it "says an OAuth handshake failed" do
      get omniauth_failure_path

      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq(I18n.t("sessions.create.oauth_failure"))
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
      expect(flash[:notice]).to eq(I18n.t("sessions.destroy.success"))
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

  describe "POST /session with suspended account" do
    let(:suspended_user) { create(:user, :suspended, failed_login_attempts: 3) }

    it "refuses sign-in, alerts, creates no session, and leaves the lockout counter alone" do
      expect {
        post session_path, params: {
          email_address: suspended_user.email_address,
          password: "SecureP@ssw0rd123!"
        }
      }.not_to change(Session, :count)

      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq(I18n.t("sessions.create.suspended"))
      # A refused sign-in is not a successful one: the counter is cleared only
      # after the session exists.
      expect(suspended_user.reload.failed_login_attempts).to eq(3)
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

  describe "resuming a session after the user is suspended mid-session" do
    it "redirects to sign in once suspend! destroys the underlying session row" do
      operator = create(:user)
      sign_in(user)

      user.suspend!(by: operator)

      get edit_settings_profile_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  # Backstop for a Session row that exists despite the user being suspended —
  # suspend! always destroys its own sessions, so this only fires if a row is
  # created some other way (or a future bug reintroduces one). Proves the
  # find_session_by_cookie check earns its place independent of that guarantee.
  describe "a live Session row for an already-suspended user" do
    it "is refused on resumption" do
      suspended_user = create(:user, :suspended)
      session_record = suspended_user.sessions.create!(
        user_agent: "RSpec", ip_address: "127.0.0.1",
        last_active_at: Time.current, reauthenticated_at: Time.current
      )
      env = Rails.application.env_config
      salt = env["action_dispatch.signed_cookie_salt"]
      secret = env["action_dispatch.key_generator"].generate_key(salt)
      verifier = ActiveSupport::MessageVerifier.new(
        secret, digest: "SHA1", serializer: ActiveSupport::MessageEncryptor::NullSerializer
      )
      cookies[:session_id] = verifier.generate(session_record.id.to_s, purpose: "cookie.session_id")

      get edit_settings_profile_path

      expect(response).to redirect_to(new_session_path)
    end
  end
end
