require "rails_helper"

RSpec.describe "Onboarding · account step", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  def signed_in_newcomer
    user = create(:user, :with_zero_workspaces)
    sign_in(user)
    user
  end

  it "renders the name-your-account form" do
    signed_in_newcomer
    get new_onboarding_workspace_path
    expect(response).to have_http_status(:ok)
  end

  it "creates the workspace + owner membership and completes onboarding" do
    user = signed_in_newcomer
    expect {
      post onboarding_workspace_path, params: { workspace: { name: "Acme Co" } }
    }.to change(Workspace.kept, :count).by(1)

    workspace = user.reload.workspaces.kept.first
    expect(workspace.name).to eq("Acme Co")
    expect(workspace.owner).to eq(user)
    expect(user.reload.onboarded?).to be(true)
    expect(response).to redirect_to(workspace_path(workspace))
    expect(flash[:notice]).to eq(I18n.t("onboarding.workspaces.create.success"))
  end

  it "re-renders on a blank name" do
    signed_in_newcomer
    post onboarding_workspace_path, params: { workspace: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
