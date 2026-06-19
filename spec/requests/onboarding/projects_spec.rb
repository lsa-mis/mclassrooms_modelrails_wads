require "rails_helper"

RSpec.describe "Onboarding · project step", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  let(:user) { create(:user, :with_zero_workspaces) }
  let(:workspace) { create(:workspace) }
  let!(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end

  before do
    workspace.memberships.create!(user: user, role: owner_role)
    sign_in(user)
  end

  it "renders the new-project form" do
    get new_onboarding_project_path
    expect(response).to have_http_status(:ok)
  end

  it "creates the project and advances to the team step" do
    expect {
      post onboarding_project_path, params: { project: { name: "Acme Website", description: "Marketing site" } }
    }.to change(workspace.projects.kept, :count).by(1)

    project = workspace.projects.kept.first
    expect(project.name).to eq("Acme Website")
    expect(project.project_memberships.find_by(user: user)&.role).to eq("creator")
    expect(response).to redirect_to(new_onboarding_team_path)
  end

  it "re-renders on a blank name" do
    expect {
      post onboarding_project_path, params: { project: { name: "" } }
    }.not_to change(workspace.projects.kept, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "redirects back to the account step if no workspace exists yet" do
    other = create(:user, :with_zero_workspaces)
    sign_in(other)
    get new_onboarding_project_path
    expect(response).to redirect_to(new_onboarding_workspace_path)
  end
end
