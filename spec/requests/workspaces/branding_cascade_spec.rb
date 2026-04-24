require "rails_helper"

RSpec.describe "Workspace branding cascade", type: :request do
  let(:user) { create(:user) }
  let!(:owner_role) { Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" } }

  describe "on workspace-scoped routes" do
    let(:workspace) { create(:workspace, primary_color: 270) }
    let!(:membership) { create(:membership, user: user, workspace: workspace, role: owner_role) }

    before { sign_in(user) }

    it "emits data-workspace-branded on <main>" do
      get workspace_path(workspace)
      expect(response.body).to match(/<main[^>]+data-workspace-branded/)
    end

    it "emits --ws-primary using the workspace's primary_color hue" do
      get workspace_path(workspace)
      expect(response.body).to include("--ws-primary: oklch(0.40 0.15 270)")
    end

    it "falls back to hue 210 when primary_color is nil" do
      workspace.update!(primary_color: nil)
      get workspace_path(workspace)
      expect(response.body).to include("--ws-primary: oklch(0.40 0.15 210)")
    end
  end

  describe "on non-workspace routes" do
    it "does not emit data-workspace-branded on the home page" do
      get root_path
      expect(response.body).not_to include("data-workspace-branded")
    end

    it "does not emit data-workspace-branded on the home page when signed in" do
      sign_in(user)
      get root_path
      expect(response.body).not_to include("data-workspace-branded")
    end
  end
end
