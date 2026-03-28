require "rails_helper"

RSpec.describe "Passwords", type: :request do
  let(:user) { create(:user) }

  describe "GET /passwords/new" do
    it "renders the forgot password form" do
      get new_password_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /passwords" do
    it "sends a reset email for valid email" do
      expect {
        post passwords_path, params: { email_address: user.email_address }
      }.to have_enqueued_mail(AuthenticationMailer, :password_reset_email)
    end

    it "does not reveal whether email exists" do
      post passwords_path, params: { email_address: "nonexistent@example.com" }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /passwords/:token/edit" do
    it "renders the reset form for valid token" do
      token = user.password_reset_token
      get edit_password_path(token: token)
      expect(response).to have_http_status(:ok)
    end

    it "redirects for invalid token" do
      get edit_password_path(token: "invalid")
      expect(response).to redirect_to(new_password_path)
    end
  end

  describe "PATCH /passwords/:token" do
    it "resets the password and redirects to sign in" do
      token = user.password_reset_token
      patch password_path(token: token), params: {
        user: {
          password: "NewSecureP@ss123!",
          password_confirmation: "NewSecureP@ss123!"
        }
      }
      expect(response).to redirect_to(new_session_path)
    end

    it "invalidates the token after use (password_digest changed)" do
      token = user.password_reset_token
      patch password_path(token: token), params: {
        user: {
          password: "NewSecureP@ss123!",
          password_confirmation: "NewSecureP@ss123!"
        }
      }
      # Token is now invalid because password_digest changed
      expect(User.find_by_password_reset_token(token)).to be_nil
    end
  end

  describe "POST /passwords for passwordless user (C2)" do
    let(:passwordless_user) { create(:user) }

    before { passwordless_user.update_column(:password_digest, nil) }

    it "sends a magic link instead of password reset" do
      expect {
        post passwords_path, params: { email_address: passwordless_user.email_address }
      }.to have_enqueued_mail(MagicLinkMailer, :sign_in_link)
    end

    it "does not enqueue a password reset email for passwordless user" do
      expect {
        post passwords_path, params: { email_address: passwordless_user.email_address }
      }.not_to have_enqueued_mail(AuthenticationMailer, :password_reset_email)
    end

    it "does not crash and redirects to sign in" do
      post passwords_path, params: { email_address: passwordless_user.email_address }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "PATCH /passwords/:token with mismatched passwords" do
    let(:user) { create(:user) }

    it "returns unprocessable entity" do
      token = user.password_reset_token
      patch password_path(token: token), params: {
        user: { password: "NewP@ssw0rd123!", password_confirmation: "Different123!" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /passwords/:token destroys old sessions (I5)" do
    it "destroys all existing sessions after password reset" do
      user.sessions.create!(user_agent: "old-browser", ip_address: "1.1.1.1")
      token = user.password_reset_token
      patch password_path(token: token), params: {
        user: { password: "NewSecureP@ss123!", password_confirmation: "NewSecureP@ss123!" }
      }
      expect(user.sessions.reload.count).to eq(0)
    end
  end
end
