require "rails_helper"

RSpec.describe "Onboarding · team step", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  let(:user) { create(:user, :with_zero_workspaces) }
  let(:workspace) { create(:workspace) }
  let!(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end
  let!(:member_role) do
    Role.find_or_create_by!(slug: "member", workspace_id: nil) do |r|
      r.name = "Member"
      r.permissions = { manage_projects: true }
    end
  end
  let!(:project) { create(:project, workspace: workspace) }

  before do
    workspace.memberships.create!(user: user, role: owner_role)
    sign_in(user)
  end

  it "renders the invite form" do
    get new_onboarding_team_path
    expect(response).to have_http_status(:ok)
  end

  it "sends invites, completes onboarding, and lands on the project" do
    expect {
      post onboarding_team_path, params: {
        invitation: { emails: "sam@example.com, lee@example.com", role_id: member_role.id }
      }
    }.to change(Invitation, :count).by(2)

    expect(user.reload.onboarded?).to be(true)
    expect(response).to redirect_to(workspace_project_path(workspace, project))
  end

  it "re-renders when no emails are provided" do
    post onboarding_team_path, params: { invitation: { emails: "", role_id: member_role.id } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.onboarded?).to be(false)
  end

  it "skipping (PATCH onboarding) completes onboarding without invites" do
    expect {
      patch onboarding_path
    }.not_to change(Invitation, :count)
    expect(user.reload.onboarded?).to be(true)
    expect(response).to redirect_to(workspace_project_path(workspace, project))
  end
end
