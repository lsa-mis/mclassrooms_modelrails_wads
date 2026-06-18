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
    it "stores token in session and redirects to registration" do
      post accept_invitation_path(token: invitation.token)
      expect(response).to redirect_to(new_registration_path)
    end
  end

  describe "registration with a pending invitation (deferred until verification)" do
    let!(:invitation) { create(:invitation, invitable: workspace, email: "newuser@example.com") }

    it "parks the invitation at registration and joins the workspace after email verification" do
      post accept_invitation_path(token: invitation.token)

      post registration_path, params: {
        user: {
          email_address: "newuser@example.com",
          first_name: "New",
          last_name: "User",
          password: "SecureP@ssw0rd123!",
          password_confirmation: "SecureP@ssw0rd123!"
        }
      }

      new_user = User.find_by(email_address: "newuser@example.com")
      # Email unproven at registration — not joined, invitation still pending.
      expect(new_user.workspaces).not_to include(workspace)
      expect(invitation.reload).to be_pending

      auth = new_user.authentications.email.first
      get verify_settings_connected_accounts_path(token: auth.generate_token_for(:email_verification))

      expect(new_user.reload.workspaces).to include(workspace)
      expect(invitation.reload).to be_accepted
    end
  end

  describe "project invitation auto-accept on registration" do
    let(:workspace) { create(:workspace) }
    let(:owner) { create(:user) }
    let(:project) { create(:project, workspace: workspace, created_by: owner) }
    let(:viewer_role) { Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" } }
    let!(:invitation) do
      create(:membership, :owner, user: owner, workspace: workspace)
      project.invitations.create!(
        email: "new-project-user@example.com",
        role: viewer_role,
        project_role: "editor",
        invited_by: owner,
        expires_at: 7.days.from_now
      )
    end

    it "unauthenticated user registers, then joins workspace + project after email verification" do
      post accept_invitation_path(token: invitation.token)
      expect(response).to redirect_to(new_registration_path)

      post registration_path, params: {
        user: {
          email_address: "new-project-user@example.com",
          first_name: "Project",
          last_name: "Invitee",
          password: "SecureP@ssw0rd123!",
          password_confirmation: "SecureP@ssw0rd123!"
        }
      }

      new_user = User.find_by(email_address: "new-project-user@example.com")
      # Email unproven at registration — not joined, invitation still pending.
      expect(new_user.workspaces).not_to include(workspace)
      expect(invitation.reload).to be_pending

      auth = new_user.authentications.email.first
      get verify_settings_connected_accounts_path(token: auth.generate_token_for(:email_verification))

      expect(new_user.reload.workspaces).to include(workspace)
      expect(new_user.reload.projects).to include(project)
      expect(invitation.reload).to be_accepted
    end
  end
end
