require "rails_helper"

# Controller spec (not request) because only here can we pre-seed arbitrary
# session keys to prove they're dropped at the login privilege boundary (SEC-4).
RSpec.describe SessionsController, type: :controller do
  let(:user) { create(:user, password: "SecureP@ssw0rd123!") }

  describe "POST #create — session reset on login" do
    it "drops non-preserved pre-auth session state but honors the allow-list" do
      request.session[:evil] = "planted"
      request.session[:current_workspace_id] = 999
      request.session[:return_to_after_authenticating] = "/settings/profile/edit"

      post :create, params: { email_address: user.email_address, password: "SecureP@ssw0rd123!" }

      expect(session[:evil]).to be_nil
      expect(session[:current_workspace_id]).to be_nil
      # return_to survived the reset and was consumed for the post-login redirect.
      expect(response).to redirect_to("/settings/profile/edit")
    end

    it "preserves a parked invitation token across the reset" do
      request.session[:pending_invitation_token] = "tok-123"
      post :create, params: { email_address: user.email_address, password: "SecureP@ssw0rd123!" }
      expect(session[:pending_invitation_token]).to eq("tok-123")
    end
  end
end
