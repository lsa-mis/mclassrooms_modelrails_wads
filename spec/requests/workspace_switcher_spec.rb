require "rails_helper"

RSpec.describe "Workspace switcher (header)", type: :request do
  let(:user) { create(:user) }                                  # :personal default → 1 workspace
  before { sign_in(user) }

  it "is absent when the user has only one workspace" do
    get workspaces_path
    expect(response.body).not_to include("workspace-switcher-button")
  end

  it "renders the switcher when the user has 2+ workspaces" do
    second = create(:workspace)
    create(:membership, :owner, user: user, workspace: second)
    get workspaces_path
    expect(response.body).to include("workspace-switcher-button")
    expect(response.body).to include(CGI.escapeHTML(second.name))
  end
end
