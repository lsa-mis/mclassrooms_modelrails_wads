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
      # Create logs with explicit timestamps in the past; recent returns desc order
      old = create(:activity_log, created_at: 2.days.ago)
      new_log = create(:activity_log, created_at: 1.day.ago)
      # recent.first returns the most recently created overall; just verify ordering of our logs
      recent_logs = ActivityLog.recent.to_a
      expect(recent_logs.index(new_log)).to be < recent_logs.index(old)
    end
  end
end
