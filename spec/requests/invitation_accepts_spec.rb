require "rails_helper"

RSpec.describe "Invitation Accepts", type: :request do
  let(:workspace) { create(:workspace) }
  let!(:invitation) { create(:invitation, invitable: workspace) }

  describe "GET /invitations/:token/accept" do
    it "shows the accept page" do
      get accept_invitation_path(token: invitation.token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(workspace.name))
    end

    it "shows error for expired invitation" do
      invitation.update!(expires_at: 1.day.ago)
      get accept_invitation_path(token: invitation.token)
      expect(response).to redirect_to(root_path)
    end

    it "shows error for invalid token" do
      get accept_invitation_path(token: "invalid")
      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /invitations/:token/accept (authenticated)" do
    let(:user) { create(:user) }
    # Invitation addressed to the signed-in user's email — the legitimate case.
    let!(:invitation) { create(:invitation, invitable: workspace, email: user.email_address) }
    before { sign_in(user) }

    it "accepts the invitation and creates membership" do
      expect {
        post accept_invitation_path(token: invitation.token)
      }.to change(Membership, :count).by(1)
    end

    it "redirects to the workspace" do
      post accept_invitation_path(token: invitation.token)
      expect(response).to redirect_to(workspace_path(workspace))
    end

    it "rejects an already-accepted invitation" do
      invitation.accept!(create(:user))
      post accept_invitation_path(token: invitation.token)
      expect(response).to redirect_to(root_path)
    end

    it "refuses an invitation addressed to a different email" do
      mismatched = create(:invitation, invitable: workspace, email: "someone-else@example.com")

      expect {
        post accept_invitation_path(token: mismatched.token)
      }.not_to change(Membership, :count)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("invitation_accepts.create.email_mismatch"))
    end
  end

  describe "POST /invitations/:token/accept (unauthenticated)" do
    it "stores token in session and redirects to new_session_path" do
      post accept_invitation_path(token: invitation.token)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "signup with a pending invitation via magic-link (atomic acceptance)" do
    let!(:invitation) { create(:invitation, invitable: workspace, email: "newuser@example.com") }

    before do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
    end

    it "parks the invitation token in session, then accepts it atomically on magic-link signup" do
      # Unauthenticated POST to accept → stashes token in session, redirects to sign-in.
      post accept_invitation_path(token: invitation.token)
      expect(response).to redirect_to(new_session_path)

      # Simulate magic-link signup: create a token and POST the callback with the
      # invitation token still in session (the request helper carries the cookie).
      token = MagicLinkToken.create_for_email("newuser@example.com")
      expect {
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "New", last_name: "User" }
        }
      }.to change(User, :count).by(1)

      new_user = User.find_by(email_address: "newuser@example.com")
      # Magic-link signup is atomic: invitation accepted immediately (verified email).
      expect(new_user.workspaces).to include(workspace)
      expect(invitation.reload).to be_accepted
    end
  end
end
