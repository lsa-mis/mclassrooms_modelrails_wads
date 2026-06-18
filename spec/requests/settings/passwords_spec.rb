require "rails_helper"

RSpec.describe "Account Passwords", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /account/password/new to sign in" do
      get new_settings_password_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }

    before { sign_in(user) }

    describe "GET /account/password/new" do
      context "user without email auth" do
        it "renders the add password form" do
          get new_settings_password_path
          expect(response).to have_http_status(:ok)
        end
      end

      context "user with existing email auth" do
        before { create(:authentication, user: user, provider: "email", uid: user.email_address) }

        it "redirects (already has password)" do
          get new_settings_password_path
          expect(response).to redirect_to(edit_settings_profile_path)
        end
      end
    end

    describe "POST /account/password" do
      it "creates email authentication and updates password" do
        expect {
          post settings_password_path, params: {
            user: {
              password: "NewSecureP@ss123!",
              password_confirmation: "NewSecureP@ss123!"
            }
          }
        }.to change(user.authentications.email, :count).by(1)
      end

      describe "POST /account/password with invalid password" do
        it "returns unprocessable entity for short password" do
          post settings_password_path, params: {
            user: { password: "short", password_confirmation: "short" }
          }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context "user already has email auth" do
        before { create(:authentication, user: user, provider: "email", uid: user.email_address) }

        it "redirects without creating" do
          post settings_password_path, params: {
            user: {
              password: "NewSecureP@ss123!",
              password_confirmation: "NewSecureP@ss123!"
            }
          }
          expect(response).to redirect_to(edit_settings_profile_path)
        end
      end
    end
  end
end
