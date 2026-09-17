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

  # Suspendable#suspend!/#unsuspend! are guarded `update!` calls, so a
  # lock/unlock arrives as workspace.updated with suspended_at in changes —
  # the same shape membership.updated splits on discarded_at.
  describe "#display_action for workspace suspension" do
    it "names a suspension and an unsuspension from the row's changes" do
      suspended = ActivityLog.new(action: "workspace.updated", metadata: { changes: { suspended_at: [ nil, Time.current ] } })
      unsuspended = ActivityLog.new(action: "workspace.updated", metadata: { changes: { suspended_at: [ Time.current, nil ] } })
      renamed = ActivityLog.new(action: "workspace.updated", metadata: { changes: { name: [ "a", "b" ] } })

      expect(suspended.display_action).to eq("workspace.suspended")
      expect(unsuspended.display_action).to eq("workspace.unsuspended")
      expect(renamed.display_action).to eq("workspace.updated")
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

    # include/not_to include rather than contain_exactly: the workspace's own
    # `workspace.created` row belongs to this scope too (Workspace answers
    # activity_workspace for itself, #1084). The old exact match only held
    # because that row used to be written with a nil workspace — the scope
    # was passing on a defect, and pinning the row COUNT was never its job.
    it ".for_workspace filters by workspace" do
      ws_log = create(:activity_log, workspace: workspace)
      other_log = create(:activity_log, workspace: create(:workspace))

      expect(ActivityLog.for_workspace(workspace)).to include(ws_log)
      expect(ActivityLog.for_workspace(workspace)).not_to include(other_log)
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
      user # materialize before the count block — creating a user writes its own activity rows.
      expect {
        expect {
          ActivityLog.record_security_event!(action: "user.passkey_add", user: user)
        }.to raise_error(ArgumentError, /SECURITY_ACTIONS/)
      }.not_to change(ActivityLog, :count)
    end

    # Operatorship's actor is the granter/revoker, not the subject — actor:
    # and visibility: let a caller override the self-event default so the
    # row still fits that writer's shape.
    it "writes an operator-actor row at admin visibility when given actor: and visibility:" do
      operator = create(:user)
      log = ActivityLog.record_security_event!(action: "operatorship.granted", user: user,
                                              actor: operator, visibility: "admin",
                                              metadata: { operatorship_id: 1 })

      expect(log).to have_attributes(actor: operator, trackable: user, visibility: "admin", workspace_id: nil)
    end

    it "accepts an explicit nil actor (a rake grant has no granter)" do
      log = ActivityLog.record_security_event!(action: "operatorship.granted", user: user,
                                              actor: nil, visibility: "admin")

      expect(log.actor).to be_nil
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

  describe "#display_member" do
    # The operations feed is the first surface to render admin-visibility
    # rows (the workspace feed is workspace-only, the account security card
    # is personal-only), and an operatorship grant's trackable is the
    # grantee User — not a Membership — so without this case
    # display_member returns nil and the sentence substitutes "a member".
    it "names the grantee for an operatorship grant, whose trackable is a User" do
      grantee = create(:user, first_name: "Gale", last_name: "Grantee")
      Operatorship.grant!(user: grantee)
      log = ActivityLog.find_by!(action: "operatorship.granted", trackable: grantee)

      expect(log.display_member).to eq("Gale Grantee")
    end
  end

  describe ".for_operations_feed" do
    it "includes workspace and admin tiers across workspaces and excludes personal rows, newest first" do
      w1 = create(:workspace)
      w2 = create(:workspace)
      # trackable is a required polymorphic belongs_to; the workspace itself is
      # a cheap valid target here since only visibility/ordering are under test.
      older = ActivityLog.create!(action: "project.created", workspace: w1, visibility: "workspace", created_at: 2.days.ago, trackable: w1)
      admin = ActivityLog.create!(action: "membership.updated", workspace: w2, visibility: "admin", created_at: 1.day.ago, trackable: w2)
      personal = ActivityLog.create!(action: "user.passkey_added", workspace: nil, visibility: "personal", trackable: create(:user))

      # create(:workspace) itself writes a workspace.created row (Trackable),
      # so an exact-array match would break on that incidental noise — assert
      # membership and order instead.
      feed = ActivityLog.for_operations_feed.to_a

      expect(feed).to include(admin, older)
      expect(feed).not_to include(personal)
      expect(feed.index(admin)).to be < feed.index(older)
    end
  end

  # Pins Bullet's internals on purpose: .preload_trackables reading the
  # association internally (`rows.filter_map(&:trackable)`) to build a
  # discarded array previously marked the User hop "used" regardless of
  # whether any caller read it, masking a real unused eager load. This calls
  # Bullet::Detector::UnusedEagerLoading directly to check that marking, so a
  # Bullet upgrade that changes it breaks here, not mysteriously elsewhere.
  describe ".for_feed Bullet visibility" do
    it "leaves an unread User trackable hop visible to Bullet's unused-eager-load detector" do
      2.times { Operatorship.grant!(user: create(:user)) }

      Bullet.start_request
      ActivityLog.where(action: "operatorship.granted").for_feed
      Bullet::Detector::UnusedEagerLoading.check_unused_preload_associations
      unused = Bullet.notification_collector.collection
        .select { |notification| notification.base_class == "ActivityLog" }
        .flat_map(&:associations)

      expect(unused).to include(:trackable)
    ensure
      Bullet.end_request
    end
  end
end
