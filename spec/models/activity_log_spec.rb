require "rails_helper"

RSpec.describe ActivityLog, type: :model do
  # #932: a deactivation and a reactivation are both `membership.updated`, so
  # the feed called every one of them a role change. These run against rows
  # Trackable actually wrote, not hand-built metadata — the concern stores
  # `{ changes: … }` under a SYMBOL key on the in-memory row and a string key
  # once reloaded, and the derivation has to read both.
  describe "#display_action" do
    let(:workspace) { create(:workspace) }
    let(:owner) { create(:user) }
    let(:membership) { create(:membership, workspace: workspace) }

    before do
      create(:membership, :owner, user: owner, workspace: workspace)
      Current.session = owner.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      Current.workspace = workspace
      membership
    end

    after do
      Current.session = nil
      Current.workspace = nil
    end

    def last_membership_update
      ActivityLog.where(trackable: membership, action: "membership.updated").order(:created_at).last
    end

    it "names a removal a deactivation" do
      membership.deactivate!

      expect(last_membership_update.display_action).to eq("membership.deactivated")
    end

    it "names a re-admission a reactivation" do
      membership.deactivate!
      membership.reactivate!(granted_by: owner)

      expect(last_membership_update.display_action).to eq("membership.reactivated")
    end

    it "leaves a role change as the plain update" do
      membership.change_role!(Role.system_default!("admin"))

      expect(last_membership_update.display_action).to eq("membership.updated")
    end

    it "reads the symbol-keyed metadata of a row that has not been reloaded" do
      membership.deactivate!
      row = ActivityLog.where(trackable: membership, action: "membership.updated").order(:created_at).last

      expect(row.metadata.keys.map(&:to_s)).to include("changes")
      expect(row.display_action).to eq("membership.deactivated")
    end

    it "leaves every other action alone" do
      expect(build(:activity_log, action: "project.created").display_action).to eq("project.created")
    end
  end

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

  describe ".security_events_for" do
    let(:user) { create(:user) }

    it "returns only SECURITY_ACTIONS rows for that user, newest first" do
      travel_to(2.hours.ago) { ActivityLog.record_security_event!(action: "user.passkey_added", user: user) }
      newest = ActivityLog.record_security_event!(action: "user.password_changed", user: user)
      # Same user, personal visibility, but not a security action — the case
      # a visibility-keyed query would wrongly include (#827).
      create(:activity_log, :security, action: "workspace.updated", actor: user)
      ActivityLog.record_security_event!(action: "user.password_changed", user: create(:user))

      result = ActivityLog.security_events_for(user)

      expect(result.map(&:action)).to eq([ "user.password_changed", "user.passkey_added" ])
      expect(result.first).to eq(newest)
    end

    # Without created_at on the trackable index, LIMIT does not bound the work:
    # SQLite materializes every row for the user, builds a temp B-tree, sorts,
    # then discards all but 10 (#823).
    it "sorts on the index rather than in a temp B-tree" do
      plan = ActivityLog.security_events_for(user).limit(10).explain.inspect
      expect(plan).to include("index_activity_logs_on_trackable_and_created_at")
      expect(plan).not_to include("USE TEMP B-TREE FOR ORDER BY")
      expect(plan).not_to match(/SCAN activity_logs[^_]/)
    end
  end

  describe "personal visibility" do
    it "accepts visibility: personal" do
      user = create(:user)
      log = ActivityLog.create!(
        action: "user.password_changed",
        actor: user,
        trackable: user,
        visibility: "personal",
        workspace_id: nil
      )
      expect(log.reload.visibility).to eq("personal")
    end

    it "is excluded from the workspace-visible scope" do
      user = create(:user)
      create(:activity_log, :security, action: "user.password_changed", actor: user)
      expect(ActivityLog.visible.where(trackable: user)).to be_empty
    end

    it "rejects unknown visibility values at the database" do
      expect {
        ActivityLog.connection.execute(<<~SQL)
          INSERT INTO activity_logs (action, trackable_type, trackable_id, visibility, created_at, updated_at)
          VALUES ('x', 'User', 1, 'bogus', datetime('now'), datetime('now'))
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /activity_logs_visibility_valid/)
    end
  end

  describe ".record_security_event!" do
    let(:user) { create(:user) }

    it "writes the personal, workspace-less row shape shared by every security writer" do
      log = ActivityLog.record_security_event!(action: "user.passkey_added", user: user,
                                              metadata: { nickname: "laptop" })

      expect(log).to have_attributes(
        action: "user.passkey_added", actor: user, trackable: user,
        visibility: "personal", workspace_id: nil, metadata: { "nickname" => "laptop" }
      )
    end

    it "defaults metadata to empty rather than nil" do
      log = ActivityLog.record_security_event!(action: "user.password_changed", user: user)
      expect(log.reload.metadata).to eq({})
    end

    # The guard is the point of the method: a drifted literal would otherwise
    # write a plausible row that the retention sweep deletes at 12 months
    # instead of the security floor, with every other spec still green.
    it "raises instead of writing when the action is outside SECURITY_ACTIONS" do
      user # Ruling R7: materialize before the count block — onboarding writes its own rows.
      expect {
        expect {
          ActivityLog.record_security_event!(action: "user.passkey_add", user: user)
        }.to raise_error(ArgumentError, /SECURITY_ACTIONS/)
      }.not_to change(ActivityLog, :count)
    end
  end

  # settings/sessions/index.html.erb builds its row label from this constant
  # dynamically (t("settings.sessions.activity.#{action}")), which a static
  # scanner can't resolve — config/i18n-tasks.yml's ignore_unused entry for
  # that namespace suppresses the "unused key" signal, so this is the only
  # thing that still catches a label going stale in either direction: a
  # deleted key, or (the case this arc will hit as later PRs add security
  # actions) a new SECURITY_ACTIONS entry that ships without one.
  describe "SECURITY_ACTIONS have a settings.sessions.activity label" do
    ActivityLog::SECURITY_ACTIONS.each do |action|
      it "has a translation for #{action}" do
        expect(I18n.exists?("settings.sessions.activity.#{action}")).to be(true)
      end
    end
  end
end
