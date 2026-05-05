# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceCapacitySweepJob, type: :job do
  include ActiveJob::TestHelper

  let(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end

  before do
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
    clear_enqueued_jobs
  end

  describe "#perform" do
    it "dispatches WorkspaceCapacityApproachingNotifier when a workspace is at >= 80% of max_members" do
      workspace = create(:workspace, max_members: 5)
      owner = create(:user)
      create(:membership, user: owner, workspace: workspace, role: owner_role)
      # Add 3 more members so kept count is 4 of 5 (80%).
      3.times { create(:membership, user: create(:user), workspace: workspace) }

      expect {
        described_class.perform_now
      }.to change { Noticed::Event.where(type: "WorkspaceCapacityApproachingNotifier").count }.by(1)

      event = Noticed::Event.where(type: "WorkspaceCapacityApproachingNotifier").last
      expect(event.params[:metric]).to eq("members")
      expect(event.params[:current]).to eq(4)
      expect(event.params[:limit]).to eq(5)
    end

    it "delivers in-app notifications to every owner of an over-threshold workspace" do
      workspace = create(:workspace, max_members: 5)
      owner_a = create(:user)
      owner_b = create(:user)
      create(:membership, user: owner_a, workspace: workspace, role: owner_role)
      create(:membership, user: owner_b, workspace: workspace, role: owner_role)
      # Bring kept count to 4 of 5 (note: each new membership above is +1)
      2.times { create(:membership, user: create(:user), workspace: workspace) }

      described_class.perform_now

      [ owner_a, owner_b ].each do |owner|
        expect(
          Noticed::Notification
            .where(recipient: owner, type: "WorkspaceCapacityApproachingNotifier::Notification").count
        ).to eq 1
      end
    end

    it "does NOT dispatch when a workspace is below 80% of max_members" do
      workspace = create(:workspace, max_members: 10)
      owner = create(:user)
      create(:membership, user: owner, workspace: workspace, role: owner_role)
      # 1 of 10 = 10% — well below threshold.

      expect {
        described_class.perform_now
      }.not_to change { Noticed::Event.where(type: "WorkspaceCapacityApproachingNotifier").count }
    end

    it "processes multiple workspaces independently" do
      ws_over = create(:workspace, max_members: 5)
      owner_over = create(:user)
      create(:membership, user: owner_over, workspace: ws_over, role: owner_role)
      3.times { create(:membership, user: create(:user), workspace: ws_over) }

      ws_under = create(:workspace, max_members: 10)
      owner_under = create(:user)
      create(:membership, user: owner_under, workspace: ws_under, role: owner_role)

      expect {
        described_class.perform_now
      }.to change { Noticed::Event.where(type: "WorkspaceCapacityApproachingNotifier").count }.by(1)

      latest = Noticed::Event.where(type: "WorkspaceCapacityApproachingNotifier").last
      expect(latest.record_id).to eq(ws_over.id)
    end

    it "skips discarded workspaces" do
      workspace = create(:workspace, max_members: 5)
      owner = create(:user)
      create(:membership, user: owner, workspace: workspace, role: owner_role)
      3.times { create(:membership, user: create(:user), workspace: workspace) }
      workspace.discard!

      expect {
        described_class.perform_now
      }.not_to change { Noticed::Event.where(type: "WorkspaceCapacityApproachingNotifier").count }
    end

    it "does not sweep the projects metric in v1 (members-only by design)" do
      # Build a workspace that's at 100% of max_projects but well under
      # max_members — confirms the sweep does not emit a projects-metric event.
      workspace = create(:workspace, max_members: 100, max_projects: 1)
      owner = create(:user)
      create(:membership, user: owner, workspace: workspace, role: owner_role)
      create(:project, workspace: workspace, created_by: owner)

      expect {
        described_class.perform_now
      }.not_to change { Noticed::Event.where(type: "WorkspaceCapacityApproachingNotifier").count }
    end
  end
end
