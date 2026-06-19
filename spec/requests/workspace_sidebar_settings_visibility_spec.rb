require "rails_helper"

RSpec.describe "Workspace sidebar Settings item visibility", type: :request do
  # Personal workspaces suppress the "Settings" nav item — identity settings
  # live in the avatar-menu hub (Phase 1 of the workspace-settings IA refactor).
  # Org workspaces retain the Settings link as the entry to the admin hub.

  it "is hidden on a personal workspace" do
    user = create(:user)                        # :user factory creates one personal workspace
    sign_in(user)
    get workspace_path(user.workspaces.kept.sole)
    expect(response.body).not_to include(edit_workspace_path(user.workspaces.kept.sole))
  end

  it "is shown on an org workspace" do
    user = create(:user)
    org  = create(:workspace)                   # non-personal (personal: false by default)
    create(:membership, :owner, user: user, workspace: org)
    sign_in(user)
    get workspace_path(org)
    expect(response.body).to include(edit_workspace_path(org))
  end
end
