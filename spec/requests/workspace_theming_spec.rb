require "rails_helper"

RSpec.describe "Workspace theming (main element)", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  it "renders a personal workspace desaturated (data-workspace-kind=personal, no hue brand)" do
    personal = user.workspaces.kept.find(&:personal?)
    get workspace_path(personal)
    expect(response.body).to include('data-workspace-kind="personal"')
    expect(response.body).not_to match(/data-workspace-branded[^>]*--ws-primary/)
  end

  it "renders an org workspace at the default hue with the brand's own tokens" do
    org = create(:workspace, primary_color: Identity::DEFAULT_HUE)
    create(:membership, :owner, user: user, workspace: org)
    get workspace_path(org)
    expect(response.body).not_to include("data-workspace-branded")
    expect(response.body).not_to include("--ws-primary")
  end

  it "renders an org workspace branded with its hue" do
    org = create(:workspace, primary_color: 145)
    create(:membership, :owner, user: user, workspace: org)
    get workspace_path(org)
    expect(response.body).to include("data-workspace-branded")
    expect(response.body).to include("oklch(0.40 0.15 145)")
  end
end
