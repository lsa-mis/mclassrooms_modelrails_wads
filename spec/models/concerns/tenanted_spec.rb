require "rails_helper"

RSpec.describe Tenanted, type: :model do
  # Use Project as the host model (includes Tenanted)

  describe ".for_current_workspace" do
    let(:workspace1) { create(:workspace) }
    let(:workspace2) { create(:workspace) }
    let(:user) { create(:user) }

    before do
      create(:membership, user: user, workspace: workspace1)
      create(:membership, user: user, workspace: workspace2)
    end

    it "filters by Current.workspace" do
      project1 = create(:project, workspace: workspace1, created_by: user)
      project2 = create(:project, workspace: workspace2, created_by: user)
      Current.workspace = workspace1
      expect(Project.for_current_workspace).to include(project1)
      expect(Project.for_current_workspace).not_to include(project2)
    end

    it "returns none when Current.workspace is nil" do
      create(:project, workspace: workspace1, created_by: user)
      Current.workspace = nil
      expect(Project.for_current_workspace).to be_empty
    end
  end
end
