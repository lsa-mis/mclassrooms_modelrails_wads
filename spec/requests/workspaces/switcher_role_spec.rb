require "rails_helper"

RSpec.describe "Workspace switcher role line", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme") }

  before { sign_in(user) }

  def role_line
    Nokogiri::HTML(response.body).at_css("#workspace-identity-role")
  end

  # The other member is created FIRST and given a different role on purpose:
  # that is what makes this fail for an implementation reaching for the
  # workspace's first (or owner) membership rather than the viewer's own.
  # Reverse the creation order and the bug passes.
  it "names the signed-in user's own role, not another member's" do
    create(:membership, :owner, user: create(:user), workspace: workspace)
    create(:membership, :admin, user: user, workspace: workspace)

    get workspace_path(workspace)

    expect(role_line).not_to be_nil
    expect(role_line.text.strip).to eq("Admin")
  end

  it "shows the role on every shell page, not just the Overview" do
    create(:membership, :owner, user: user, workspace: workspace)

    [ workspace_path(workspace), workspace_projects_path(workspace) ].each do |path|
      get path
      expect(role_line&.text&.strip).to eq("Owner"), "#{path}: expected the switcher to name the role"
    end
  end
end
