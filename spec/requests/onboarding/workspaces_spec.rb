require "rails_helper"

RSpec.describe "Onboarding · account step", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  let(:user) { create(:user, :with_zero_workspaces) }
  let!(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end

  before { sign_in(user) }

  it "renders the name-your-account form" do
    get new_onboarding_workspace_path
    expect(response).to have_http_status(:ok)
  end

  it "creates the workspace + owner membership and advances to the project step" do
    expect {
      post onboarding_workspace_path, params: { workspace: { name: "Acme Co" } }
    }.to change(Workspace.kept, :count).by(1)

    workspace = user.reload.workspaces.kept.first
    expect(workspace.name).to eq("Acme Co")
    expect(workspace.owner).to eq(user)
    expect(response).to redirect_to(new_onboarding_project_path)
  end

  it "re-renders on a blank name" do
    post onboarding_workspace_path, params: { workspace: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
