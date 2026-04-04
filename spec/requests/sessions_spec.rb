require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:user) { create(:user) }

  describe "GET /session/new" do
    it "renders the sign in form" do
      get new_session_path
      expect(response).to have_http_status(:ok)
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

  describe "POST /session/lookup (smart routing)" do
    context "user with password" do
      let(:user) { create(:user) }

      it "returns the password form" do
        post session_lookup_path, params: { email_address: user.email_address }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.lookup.password_prompt"))
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
      it "shows identical check email message (no information leakage)" do
        post session_lookup_path, params: { email_address: "ghost@example.com" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.check_email.title"))
        expect(response.body).to include("ghost@example.com")
      end
    end

    context "invalid email format" do
      it "rejects email without a domain TLD" do
        post session_lookup_path, params: { email_address: "hd@humbledaisy" }
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to eq(I18n.t("sessions.lookup.invalid_email"))
      end

      it "rejects email without any structure" do
        post session_lookup_path, params: { email_address: "notanemail" }
        expect(response).to redirect_to(new_session_path)
      end

      it "rejects blank email" do
        post session_lookup_path, params: { email_address: "" }
        expect(response).to redirect_to(new_session_path)
      end
    end
  end
end
