require "rails_helper"

RSpec.describe ActivityLog, type: :model do
  describe "validations" do
    it "requires an action" do
      log = build(:activity_log, action: nil)
      expect(log).not_to be_valid
    end

    it "requires a trackable" do
      log = build(:activity_log, trackable: nil)
      expect(log).not_to be_valid
    end

    it "allows nil actor" do
      log = build(:activity_log, actor: nil)
      expect(log).to be_valid
    end

    it "allows nil workspace" do
      log = build(:activity_log, workspace: nil)
      expect(log).to be_valid
    end
  end

  describe "immutability" do
    it "allows creation (the audit trail must keep accepting writes)" do
      expect { create(:activity_log) }.not_to raise_error
    end

    it "raises on update of a persisted row" do
      log = create(:activity_log)
      expect { log.update!(action: "rewritten") }
        .to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises on destroy of a persisted row" do
      log = create(:activity_log)
      expect { log.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe "visibility enum" do
    it "defaults to workspace" do
      expect(ActivityLog.new.visibility).to eq("workspace")
    end

    it "supports admin" do
      log = build(:activity_log, visibility: "admin")
      expect(log).to be_admin
    end
  end

  describe "scopes" do
    let(:workspace) { create(:workspace) }

    it ".for_workspace filters by workspace" do
      ws_log = create(:activity_log, workspace: workspace)
      create(:activity_log, workspace: create(:workspace))
      expect(ActivityLog.for_workspace(workspace)).to contain_exactly(ws_log)
    end

    it ".visible returns workspace-visibility logs" do
      # Exclude any auto-created logs from Trackable (workspace creation etc.)
      admin_log = create(:activity_log, visibility: "admin")
      expect(ActivityLog.visible).not_to include(admin_log)
      expect(ActivityLog.visible.map(&:visibility)).to all(eq("workspace"))
    end

    it ".recent orders by created_at desc" do
      old = create(:activity_log, created_at: 2.days.ago)
      new_log = create(:activity_log, created_at: 1.day.ago)
      # recent.first returns the most recently created overall; just verify ordering of our logs
      recent_logs = ActivityLog.recent.to_a
      expect(recent_logs.index(new_log)).to be < recent_logs.index(old)
    end
  end

  # #680: the project feed's 4-way OR had no workspace predicate — a full scan
  # of the global 12-month activity table to render one project page.
  describe ".for_project" do
    let(:workspace) { create(:workspace) }
    let(:member) { create(:user).tap { |u| create(:membership, user: u, workspace: workspace) } }
    let(:project) { create(:project, workspace: workspace, created_by: member) }

    def old_view_expression(project)
      ActivityLog.visible.where(trackable: project.resources)
        .or(ActivityLog.visible.where(trackable: project))
        .or(ActivityLog.visible.where(trackable: project.project_memberships))
        .or(ActivityLog.visible.where(trackable: project.invitations))
    end

    it "returns exactly the rows the old 4-way OR returned (characterization)" do
      resource = create(:resource, project: project)
      logs = [
        create(:activity_log, trackable: project, workspace: workspace),
        create(:activity_log, trackable: resource, workspace: workspace),
        create(:activity_log, trackable: project.project_memberships.first, workspace: workspace)
      ]
      create(:activity_log, trackable: create(:workspace)) # unrelated decoy
      create(:activity_log, trackable: project, workspace: workspace, visibility: "admin")

      expect(ActivityLog.for_project(project).to_a).to match_array(old_view_expression(project).to_a)
      expect(ActivityLog.for_project(project)).to include(*logs)
    end

    it "rides the workspace index instead of scanning the table" do
      plan = ActivityLog.for_project(project).recent.explain.inspect
      expect(plan).to include("index_activity_logs_on_workspace_id_and_created_at")
      expect(plan).not_to match(/SCAN activity_logs[^_]/)
    end
  end
end
