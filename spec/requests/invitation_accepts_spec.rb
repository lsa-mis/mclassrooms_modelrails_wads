require "rails_helper"

RSpec.describe "Invitation Accepts", type: :request do
  def pending_invitation(workspace = create(:workspace), **attrs)
    create(:invitation, invitable: workspace, **attrs)
  end

  def viewer_role
    Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" }
  end

  describe "GET /invitations/:token/accept" do
    it "shows the accept page" do
      workspace = create(:workspace)
      invitation = pending_invitation(workspace)
      get accept_invitation_path(token: invitation.token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(workspace.name))
    end

    # Roles are workspace-defined, so no hard-coded article fits them (#1151).
    it "names the role without an article that may not fit it" do
      workspace = create(:workspace)
      pending_invitation(workspace)
      owner_role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" }
      owner_invitation = create(:invitation, invitable: workspace, role: owner_role)

      get accept_invitation_path(token: owner_invitation.token)

      expect(response.body).to include(
        ERB::Util.html_escape(
          I18n.t("invitation_accepts.show.body",
                 inviter: owner_invitation.invited_by.full_name,
                 workspace_name: workspace.name,
                 role: "Owner")
        )
      )
      expect(response.body).not_to include("a Owner")
    end

    it "renders the register link as a brand-outline button" do
      invitation = pending_invitation
      get accept_invitation_path(token: invitation.token)
      expect(Capybara.string(response.body)).to have_css("a.btn-outline-primary.w-full",
        text: I18n.t("invitation_accepts.show.register"))
    end

    it "shows error for expired invitation" do
      invitation = pending_invitation
      invitation.update!(expires_at: 1.day.ago)
      get accept_invitation_path(token: invitation.token)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("invitation_accepts.expired_or_used"))
    end

    it "shows error for invalid token" do
      get accept_invitation_path(token: "invalid")
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("invitation_accepts.invalid_token"))
    end
  end

  # `find_valid_invitation` is shared by #show and #create, so the rejection
  # flashes must resolve for both. Asserting the message (not just the
  # redirect) is what catches a key that only exists under one action.
  describe "POST /invitations/:token/accept (rejected tokens)" do
    it "shows error for invalid token" do
      post accept_invitation_path(token: "invalid")
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("invitation_accepts.invalid_token"))
    end

    it "shows error for expired invitation" do
      invitation = pending_invitation
      invitation.update!(expires_at: 1.day.ago)
      post accept_invitation_path(token: invitation.token)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("invitation_accepts.expired_or_used"))
    end
  end

  describe "POST /invitations/:token/accept (authenticated)" do
    def sign_in_with_invitation
      user = create(:user)
      workspace = create(:workspace)
      invitation = pending_invitation(workspace, email: user.email_address)
      sign_in(user)
      [ workspace, invitation ]
    end

    it "accepts the invitation and creates membership" do
      _workspace, invitation = sign_in_with_invitation
      expect {
        post accept_invitation_path(token: invitation.token)
      }.to change(Membership, :count).by(1)
    end

    it "redirects to the workspace and confirms acceptance" do
      workspace, invitation = sign_in_with_invitation
      post accept_invitation_path(token: invitation.token)
      expect(response).to redirect_to(workspace_path(workspace))
      expect(flash[:notice]).to eq(I18n.t("invitation_accepts.create.success"))
    end

    it "rejects an already-accepted invitation" do
      _workspace, invitation = sign_in_with_invitation
      invitation.accept!(create(:user))
      post accept_invitation_path(token: invitation.token)
      expect(response).to redirect_to(root_path)
      # Caught by find_valid_invitation, NOT the NotAcceptable rescue; only the
      # message distinguishes them (acceptance_failed is a different path).
      expect(flash[:alert]).to eq(I18n.t("invitation_accepts.expired_or_used"))
    end

    it "refuses an invitation addressed to a different email" do
      workspace, _invitation = sign_in_with_invitation
      mismatched = pending_invitation(workspace, email: "someone-else@example.com")

      expect {
        post accept_invitation_path(token: mismatched.token)
      }.not_to change(Membership, :count)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("invitation_accepts.create.email_mismatch"))
    end
  end

  describe "POST /invitations/:token/accept (unauthenticated)" do
    # Most invitees arrive signed out; assert the flash the visitor reads, not
    # just the redirect.
    it "stores token in session and redirects to new_session_path" do
      invitation = pending_invitation
      post accept_invitation_path(token: invitation.token)
      expect(response).to redirect_to(new_session_path)
      expect(flash[:notice]).to eq(I18n.t("invitation_accepts.create.register_first"))
    end
  end

  describe "signup with a pending invitation via magic-link (atomic acceptance)" do
    before do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
    end

    it "parks the invitation token in session, then accepts it atomically on magic-link signup" do
      workspace = create(:workspace)
      invitation = pending_invitation(workspace, email: "newuser@example.com")
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
