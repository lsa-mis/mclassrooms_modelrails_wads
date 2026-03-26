require "rails_helper"

RSpec.describe "Project Invitations", type: :request do
  let(:workspace) { create(:workspace) }
  let(:user) { create(:user) }
  let!(:ws_membership) { create(:membership, :owner, user: user, workspace: workspace) }
  let(:project) { create(:project, workspace: workspace, created_by: user) }
  let!(:creator_pm) { create(:project_membership, :creator, project: project, user: user) }

  before do
    Current.workspace = workspace
    sign_in(user)
  end

  describe "GET new project invitation" do
    it "renders the invitation form" do
      get new_workspace_project_invitation_path(workspace, project)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST create project invitation" do
    it "creates an invitation for a non-workspace member" do
      expect {
        post workspace_project_invitations_path(workspace, project), params: {
          invitation: { email: "outsider@example.com", project_role: "editor" }
        }
      }.to change(Invitation, :count).by(1)
        .and have_enqueued_mail(InvitationMailer, :invite)
    end

    it "rejects creator role in project_role" do
      post workspace_project_invitations_path(workspace, project), params: {
        invitation: { email: "outsider@example.com", project_role: "creator" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects invalid email" do
      post workspace_project_invitations_path(workspace, project), params: {
        invitation: { email: "not-an-email", project_role: "editor" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "accepting a project invitation" do
    let(:viewer_role) { Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" } }
    let!(:invitation) do
      project.invitations.create!(
        email: "invitee@example.com",
        role: viewer_role,
        project_role: "editor",
        invited_by: user,
        expires_at: 7.days.from_now
      )
    end

    it "auto-adds invitee to workspace and project" do
      invitee = create(:user, email_address: "invitee@example.com")
      sign_in(invitee)
      post accept_invitation_path(token: invitation.token)
      expect(invitee.workspaces).to include(workspace)
      expect(invitee.projects).to include(project)
    end

    it "assigns the correct project role" do
      invitee = create(:user, email_address: "invitee@example.com")
      sign_in(invitee)
      post accept_invitation_path(token: invitation.token)
      pm = project.project_memberships.find_by(user: invitee)
      expect(pm).to be_editor
    end

    it "rejects acceptance of archived project invitation" do
      project.discard!
      invitee = create(:user, email_address: "invitee2@example.com")
      invitation2 = project.invitations.create!(
        email: "invitee2@example.com",
        role: viewer_role,
        project_role: "editor",
        invited_by: user,
        expires_at: 7.days.from_now
      )
      sign_in(invitee)
      post accept_invitation_path(token: invitation2.token)
      expect(response).to redirect_to(root_path)
    end
  end
end
