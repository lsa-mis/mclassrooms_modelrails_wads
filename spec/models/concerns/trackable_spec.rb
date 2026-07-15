require "rails_helper"

RSpec.describe Trackable, type: :model do
  # Use Workspace as host model. Note: every create(:user) creates a personal workspace
  # which will trigger Trackable too. Tests account for this.

  def with_session(user)
    session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    Current.session = session
    yield
  ensure
    Current.session = nil
  end

  describe "auto-tracking on create" do
    it "creates an activity log when a tracked record is created" do
      user = create(:user)
      with_session(user) do
        workspace = Workspace.create!(name: "Tracked Workspace")
        log = ActivityLog.where(trackable: workspace, action: "workspace.created").last
        expect(log).to be_present
        expect(log.actor).to eq(user)
      end
    end
  end

  describe "auto-tracking on update" do
    it "creates an activity log with changes on update" do
      workspace = create(:workspace, name: "Original")
      user = create(:user)
      with_session(user) do
        workspace.update!(name: "Updated")
        log = ActivityLog.where(trackable: workspace, action: "workspace.updated").last
        expect(log).to be_present
        expect(log.metadata["changes"]).to include("name")
      end
    end

    it "skips tracking when only timestamps change" do
      workspace = create(:workspace)
      user = create(:user)
      initial_count = ActivityLog.count
      with_session(user) do
        workspace.touch
      end
      # touch only changes updated_at which is excluded
      expect(ActivityLog.count).to eq(initial_count)
    end
  end

  describe "sensitive attribute filtering" do
    it "strips token fields from metadata" do
      invitation = create(:invitation)
      user = create(:user)
      with_session(user) do
        invitation.resend!
        log = ActivityLog.where(trackable: invitation, action: "invitation.updated").last
        expect(log).to be_present
        expect(log.metadata.fetch("changes", {}).keys).not_to include("token")
      end
    end
  end

  describe "failure resilience" do
    it "does not break the primary operation on tracking failure" do
      allow(ActivityLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(ActivityLog.new))
      expect {
        Workspace.create!(name: "Should still work")
      }.to change(Workspace, :count).by(1)
    end

    it "logs the failing record's class and id so the silent loss is debuggable" do
      allow(ActivityLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(ActivityLog.new))
      allow(Rails.logger).to receive(:warn).and_call_original

      workspace = Workspace.create!(name: "Logged Failure")

      expect(Rails.logger).to have_received(:warn)
        .with(a_string_including("Workspace", workspace.id.to_s))
    end

    it "does not break the primary operation when the activity insert fails beyond validation errors" do
      allow(ActivityLog).to receive(:create!)
        .and_raise(ActiveRecord::StatementInvalid.new("SQLite3::ReadOnlyException: attempt to write a readonly database"))
      expect {
        Workspace.create!(name: "Survives statement failure")
      }.to change(Workspace, :count).by(1)
    end

    it "reports non-validation tracking failures to the error reporter" do
      error = ActiveRecord::StatementInvalid.new("boom")
      allow(ActivityLog).to receive(:create!).and_raise(error)
      allow(Rails.error).to receive(:report)

      Workspace.create!(name: "Reported Failure")

      expect(Rails.error).to have_received(:report)
        .with(error, hash_including(handled: true))
    end
  end

  describe "workspace resolution" do
    it "resolves workspace from record's workspace association" do
      workspace = create(:workspace)
      user = create(:user)
      create(:membership, :owner, user: user, workspace: workspace)
      with_session(user) do
        membership = create(:membership, workspace: workspace)
        log = ActivityLog.where(trackable: membership, action: "membership.created").last
        expect(log).to be_present
        expect(log.workspace).to eq(workspace)
      end
    end
  end
end
