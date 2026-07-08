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

  describe "POST /session/lookup (passwordless-first)" do
    it "sends a magic link to a password user instead of going straight to the password form" do
      user = create(:user) # has a password
      expect {
        post session_lookup_path, params: { email_address: user.email_address }
      }.to change { MagicLinkToken.where(email: user.email_address).count }.by(1)
      expect(response.body).to include(I18n.t("sessions.check_email.title"))
      expect(response.body).to include(I18n.t("sessions.check_email.use_password")) # secondary link present
    end

    it "blocks registration of a new email when signups are closed" do
      allow_any_instance_of(SessionsController).to receive(:signups_open?).and_return(false)
      expect {
        post session_lookup_path, params: { email_address: "newcomer@example.com" }
      }.not_to change(MagicLinkToken, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("registrations.closed.title"))
    end
  end

  describe "POST /session/lookup (smart routing)" do
    context "user with password" do
      let(:user) { create(:user) }

      it "returns check_email with secondary password link (passwordless-first)" do
        post session_lookup_path, params: { email_address: user.email_address }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.check_email.title"))
        expect(response.body).to include(I18n.t("sessions.check_email.use_password"))
      end
    end

    context "user without password" do
      let(:user) { create(:user) }

      before { user.update_column(:password_digest, nil) }

      it "shows check email confirmation inline" do
        post session_lookup_path, params: { email_address: user.email_address }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.check_email.title"))
        expect(response.body).to include(user.email_address)
        expect(response.body).to include(I18n.t("sessions.check_email.expiry"))
        expect(response.body).to include('role="status"')
      end
    end

    context "non-existent email" do
      it "shows check email when signups are open (no information leakage)" do
        allow_any_instance_of(SessionsController).to receive(:signups_open?).and_return(true)
        post session_lookup_path, params: { email_address: "ghost@example.com" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.check_email.title"))
        expect(response.body).to include("ghost@example.com")
      end

      it "shows closed view when signups are closed" do
        allow_any_instance_of(SessionsController).to receive(:signups_open?).and_return(false)
        post session_lookup_path, params: { email_address: "ghost@example.com" }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(I18n.t("registrations.closed.title"))
      end

      it "wraps the closed view in the sign_in_form turbo-frame (not 'Content missing')" do
        # The lookup form lives in <turbo-frame id="sign_in_form">, and
        # turbo-rails' frame layout does NOT auto-wrap the response. So the
        # closed view must carry a matching frame itself, or Turbo discards the
        # body and renders its built-in "Content missing" in the browser — a
        # gap the body-text assertion above cannot see (the text IS present,
        # just not inside a matching frame).
        allow_any_instance_of(SessionsController).to receive(:signups_open?).and_return(false)
        post session_lookup_path, params: { email_address: "ghost@example.com" }
        frame = Capybara.string(response.body).find("turbo-frame#sign_in_form", visible: :all)
        expect(frame).to have_text(I18n.t("registrations.closed.title"))
      end
    end

    context "retry after invalid email" do
      it "accepts the nested params submitted by the error form" do
        allow_any_instance_of(SessionsController).to receive(:signups_open?).and_return(true)

        expect {
          post session_lookup_path, params: { email_lookup_form: { email_address: "retry@example.com" } }
        }.to change { MagicLinkToken.where(email: "retry@example.com").count }.by(1)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.check_email.title"))
        expect(response.body).to include("retry@example.com")
      end
    end

    context "invalid email format" do
      it "rejects email without a domain TLD" do
        post session_lookup_path, params: { email_address: "hd@humbledaisy" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.lookup.invalid_email"))
      end

      it "rejects email without any structure" do
        post session_lookup_path, params: { email_address: "notanemail" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.lookup.invalid_email"))
      end

      it "rejects blank email" do
        post session_lookup_path, params: { email_address: "" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.lookup.invalid_email"))
      end
    end
  end
end
