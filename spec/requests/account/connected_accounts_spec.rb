require "rails_helper"

RSpec.describe "Account Connected Accounts", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  describe "GET /account/connected_accounts" do
    it "lists connected providers" do
      create(:authentication, :google, user: user)
      get account_connected_accounts_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /account/connected_accounts/:id" do
    context "with multiple auth methods" do
      let!(:email_auth) { create(:authentication, user: user, provider: "email") }
      let!(:google_auth) { create(:authentication, :google, user: user) }

      it "removes the provider" do
        expect {
          delete account_connected_account_path(google_auth)
        }.to change(user.authentications, :count).by(-1)
      end
    end

    context "with only one auth method" do
      let!(:email_auth) { create(:authentication, user: user, provider: "email") }

      it "prevents unlinking the last method" do
        delete account_connected_account_path(email_auth)
        expect(response).to redirect_to(account_connected_accounts_path)
        expect(flash[:alert]).to eq(I18n.t("account.connected_accounts.destroy.last_method"))
        expect(user.authentications.count).to eq(1)
      end
    end
  end
end
