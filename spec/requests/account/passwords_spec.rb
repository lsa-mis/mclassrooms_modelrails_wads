require "rails_helper"

RSpec.describe "Account Passwords", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  describe "GET /account/password/new" do
    context "user without email auth" do
      it "renders the add password form" do
        get new_account_password_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "user with existing email auth" do
      before { create(:authentication, user: user, provider: "email", uid: user.email_address) }

      it "redirects (already has password)" do
        get new_account_password_path
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end
  end

  describe "POST /account/password" do
    it "creates email authentication and updates password" do
      expect {
        post account_password_path, params: {
          user: {
            password: "NewSecureP@ss123!",
            password_confirmation: "NewSecureP@ss123!"
          }
        }
      }.to change(user.authentications.email, :count).by(1)
    end

    context "user already has email auth" do
      before { create(:authentication, user: user, provider: "email", uid: user.email_address) }

      it "redirects without creating" do
        post account_password_path, params: {
          user: {
            password: "NewSecureP@ss123!",
            password_confirmation: "NewSecureP@ss123!"
          }
        }
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end
  end
end
