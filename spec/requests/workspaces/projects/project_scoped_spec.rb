require "rails_helper"

# Pins the ProjectScoped contract shared by every project-scoped controller:
#
#   1. The request assigns Current.project — ResourcePolicy and
#      ProjectMembershipPolicy fall back on it for class-level `authorize`
#      calls, so a controller that skips the assignment makes those policy
#      decisions against a nil project.
#   2. An unknown project slug redirects to the workspace's projects list
#      with a specific alert (not the generic ApplicationController
#      record_not_found posture).
RSpec.describe "ProjectScoped controllers", type: :request do
  let(:workspace) { create(:workspace) }
  let(:user) { create(:user) }
  let!(:ws_membership) { create(:membership, :owner, user: user, workspace: workspace) }
  let(:project) { create(:project, workspace: workspace, created_by: user) }
  let!(:creator_pm) { create(:project_membership, :creator, project: project, user: user) }

  before do
    project.update!(clientside_enabled: true)
    sign_in(user)
  end

  {
    "Workspaces::ProjectsController#show" =>
      ->(ws, proj) { workspace_project_path(ws, proj) },
    "Workspaces::Projects::MembershipsController#index" =>
      ->(ws, proj) { workspace_project_memberships_path(ws, proj) },
    "Workspaces::Projects::InvitationsController#new" =>
      ->(ws, proj) { new_workspace_project_invitation_path(ws, proj) },
    "Workspaces::Projects::ResourcesController#index" =>
      ->(ws, proj) { workspace_project_resources_path(ws, proj) },
    "Workspaces::Projects::ToolsController#edit" =>
      ->(ws, proj) { edit_workspace_project_tools_path(ws, proj) },
    "Workspaces::Projects::ClientsidesController#edit" =>
      ->(ws, proj) { edit_workspace_project_clientside_path(ws, proj) },
    "Workspaces::Projects::ClientInvitationsController#new" =>
      ->(ws, proj) { new_workspace_project_client_invitation_path(ws, proj) }
  }.each do |controller_action, path_for|
    describe controller_action do
      it "assigns Current.project during the request" do
        assigned = []
        allow(Current).to receive(:project=).and_wrap_original do |original, value|
          assigned << value
          original.call(value)
        end

        get instance_exec(workspace, project, &path_for)

        expect(response).to have_http_status(:ok)
        expect(assigned).to include(project)
      end

      it "redirects an unknown project slug to the projects list" do
        get instance_exec(workspace, "no-such-project", &path_for)

        expect(response).to redirect_to(workspace_projects_path(workspace))
        expect(flash[:alert]).to eq(I18n.t("workspaces.projects.not_found"))
      end
    end
  end
end
