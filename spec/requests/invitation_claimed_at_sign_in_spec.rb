require "rails_helper"

RSpec.describe "An invitation parked before sign-in", type: :request do
  def sign_in_by_magic_link(user)
    token = MagicLinkToken.create_for_email(user.email_address)
    post magic_link_callback_session_path(magic_link_callback_token: token)
  end

  context "when it is addressed to the signing-in user's email" do
    def invitation_for_new_user
      workspace = create(:workspace)
      user = create(:user)
      [ workspace, user, create(:invitation, invitable: workspace, email: user.email_address) ]
    end

    it "is claimed at sign-in, landing the user in the workspace" do
      workspace, user, invitation = invitation_for_new_user
      get accept_invitation_path(token: invitation.token)
      sign_in_by_magic_link(user)

      expect(response).to redirect_to(workspace_path(workspace))
      expect(workspace.memberships.kept.exists?(user: user)).to be(true)
      expect(invitation.reload.status).to eq("accepted")
    end

    it "is claimed once: a later sign-in lands on the home page" do
      _workspace, user, invitation = invitation_for_new_user
      get accept_invitation_path(token: invitation.token)
      sign_in_by_magic_link(user)
      delete session_path
      sign_in_by_magic_link(user)

      expect(response).to redirect_to(root_path)
    end
  end

  context "when a new account registers from it" do
    it "lands the new user in the workspace it claimed" do
      email = "newcomer@example.com"
      workspace = create(:workspace)
      invitation = create(:invitation, invitable: workspace, email: email)
      get accept_invitation_path(token: invitation.token)
      token = MagicLinkToken.create_for_email(email)
      post magic_link_callback_path(token: token), params: { user: { first_name: "New", last_name: "Comer" } }

      expect(response).to redirect_to(workspace_path(workspace))
      expect(invitation.reload.accepted_by).to eq(User.find_by(email_address: email))
    end
  end

  context "when it carries no email" do
    it "is not claimed; sign-in returns the user to its accept page" do
      workspace = create(:workspace)
      invitation = create(:invitation, :magic_link, invitable: workspace)
      get accept_invitation_path(token: invitation.token)
      user = create(:user)
      sign_in_by_magic_link(user)

      expect(response).to redirect_to(accept_invitation_path(token: invitation.token))
      expect(workspace.memberships.exists?(user: user)).to be(false)
      expect(invitation.reload.status).to eq("pending")
    end
  end

  context "when it is addressed to a different email" do
    it "is not claimed, and sign-in says why" do
      workspace = create(:workspace)
      invitation = create(:invitation, invitable: workspace)
      get accept_invitation_path(token: invitation.token)
      user = create(:user)
      sign_in_by_magic_link(user)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("invitation_accepts.create.email_mismatch"))
      expect(workspace.memberships.exists?(user: user)).to be(false)
      expect(invitation.reload.status).to eq("pending")
    end
  end
end
