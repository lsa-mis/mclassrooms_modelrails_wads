require "rails_helper"

RSpec.describe "Turbo Stream broadcasts" do
  describe "workspace-level broadcasts" do
    let(:workspace) { create(:workspace) }

    it "Workspace broadcasts refresh on update" do
      expect(workspace).to receive(:broadcast_refresh_to).with(workspace)
      workspace.update!(name: "Updated Name")
    end

    it "Membership broadcasts refresh on create" do
      user = create(:user)
      membership = build(:membership, user: user, workspace: workspace)
      expect(membership).to receive(:broadcast_refresh_to).with(workspace)
      membership.save!
    end

    it "Invitation broadcasts refresh on update" do
      invitation = create(:invitation, invitable: workspace)
      expect(invitation).to receive(:broadcast_refresh_to).with(workspace)
      invitation.decline!
    end
  end

  describe "broadcast resilience" do
    it "does not break on broadcast failure" do
      workspace = create(:workspace)
      allow(workspace).to receive(:broadcast_refresh_to).and_raise(StandardError, "Redis down")
      expect { workspace.update!(name: "Still works") }.not_to raise_error
      expect(workspace.reload.name).to eq("Still works")
    end
  end
end
