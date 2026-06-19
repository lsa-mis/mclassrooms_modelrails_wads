require "rails_helper"

RSpec.describe "Onboarding dispatcher", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  let(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end

  def admit(user, workspace)
    workspace.memberships.create!(user: user, role: owner_role)
  end

  it "routes a user with no workspace to the account step" do
    user = create(:user, :with_zero_workspaces)
    sign_in(user)
    get onboarding_path
    expect(response).to redirect_to(new_onboarding_workspace_path)
  end

  it "routes a user with a workspace but no project to the project step" do
    user = create(:user, :with_zero_workspaces)
    workspace = create(:workspace)
    admit(user, workspace)
    sign_in(user)
    get onboarding_path
    expect(response).to redirect_to(new_onboarding_project_path)
  end

  it "routes a user with a workspace and a project to the team step" do
    user = create(:user, :with_zero_workspaces)
    workspace = create(:workspace)
    admit(user, workspace)
    create(:project, workspace: workspace)
    sign_in(user)
    get onboarding_path
    expect(response).to redirect_to(new_onboarding_team_path)
  end

  it "PATCH marks onboarding complete and lands on the workspace" do
    user = create(:user, :with_zero_workspaces)
    workspace = create(:workspace)
    admit(user, workspace)
    sign_in(user)
    patch onboarding_path
    expect(user.reload.onboarded?).to be(true)
    expect(response).to redirect_to(workspace_path(workspace))
  end
end
