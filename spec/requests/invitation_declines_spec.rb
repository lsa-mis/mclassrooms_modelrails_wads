require "rails_helper"

RSpec.describe "Invitation Declines", type: :request do
  let(:invitation) { create(:invitation) }

  describe "GET /invitations/:token/decline" do
    it "shows the decline page" do
      get decline_invitation_path(token: invitation.token)
      expect(response).to have_http_status(:ok)
    end

    it "shows error for invalid token" do
      get decline_invitation_path(token: "invalid")
      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /invitations/:token/decline" do
    it "declines the invitation" do
      post decline_invitation_path(token: invitation.token)
      expect(invitation.reload).to be_declined
    end

    it "redirects to root" do
      post decline_invitation_path(token: invitation.token)
      expect(response).to redirect_to(root_path)
    end
  end
end
