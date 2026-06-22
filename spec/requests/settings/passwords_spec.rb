require "rails_helper"

RSpec.describe "Account Passwords", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /account/password/new to sign in" do
      get new_settings_password_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    # Factory default: user has a password (password_digest present).
    let(:user) { create(:user) }
    # User with no password set (passwordless — signs in via magic link).
    let(:passwordless_user) { create(:user, password: nil) }

    describe "GET /account/password/new" do
      context "user without a password" do
        before { sign_in(passwordless_user) }

        it "renders the add password form" do
          get new_settings_password_path
          expect(response).to have_http_status(:ok)
        end
      end

      context "user with an existing password (already has password)" do
        before { sign_in(user) }

        it "redirects to the change-password form" do
          get new_settings_password_path
          expect(response).to redirect_to(edit_settings_password_path)
        end
      end
    end

    describe "POST /account/password" do
      context "user without a password" do
        before { sign_in(passwordless_user) }

        it "creates email authentication and updates password" do
          expect {
            post settings_password_path, params: {
              user: {
                password: "NewSecureP@ss123!",
                password_confirmation: "NewSecureP@ss123!"
              }
            }
          }.to change(passwordless_user.authentications.email, :count).by(1)
        end

        it "returns unprocessable entity for short password" do
          post settings_password_path, params: {
            user: { password: "short", password_confirmation: "short" }
          }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context "user already has a password" do
        before { sign_in(user) }

        it "redirects to the change-password form" do
          post settings_password_path, params: {
            user: {
              password: "NewSecureP@ss123!",
              password_confirmation: "NewSecureP@ss123!"
            }
          }
          expect(response).to redirect_to(edit_settings_password_path)
        end
      end
    end

    describe "PATCH /settings/password (change)" do
      before { sign_in(user) }

      it "updates the password for a user who already has one" do
        patch settings_password_path, params: { user: { password: "brand-new-passw0rd", password_confirmation: "brand-new-passw0rd" } }
        expect(user.reload.authenticate("brand-new-passw0rd")).to be_truthy
      end
    end

    describe "DELETE /settings/password (remove)" do
      before { sign_in(user) }

      it "removes the password and the email authentication, returning to passwordless" do
        delete settings_password_path
        expect(user.reload.has_password?).to be(false)
      end
    end

    describe "GET /settings/password/new for a user who already has a password" do
      before { sign_in(user) }

      it "routes them to the change form instead of add" do
        get new_settings_password_path
        expect(response).to redirect_to(edit_settings_password_path)
      end
    end
  end
end
