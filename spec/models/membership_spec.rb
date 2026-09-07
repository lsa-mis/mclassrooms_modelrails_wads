require "rails_helper"

# The core's examples; each trait's live beside it under spec/models/membership/.
RSpec.describe Membership, type: :model do
  # SEC-1: a role change is a privilege event — audit it readably (role slugs,
  # not the mutable role_id FK) and in the admin-only feed.
  describe "role-change audit trail" do
    def with_session(user)
      session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      Current.session = session
      Current.workspace = @workspace
      yield
    ensure
      Current.session = nil
      Current.workspace = nil
    end

    it "records the role slugs by value and routes the event to the admin feed" do
      @workspace = create(:workspace)
      actor = create(:user)
      create(:membership, :owner, user: actor, workspace: @workspace)
      target = create(:membership, user: create(:user), workspace: @workspace)

      with_session(actor) do
        target.change_role!(Role.system_default!("admin"))
      end

      log = ActivityLog.where(trackable: target, action: "membership.updated").order(:id).last
      expect(log.metadata["changes"]["role"]).to eq([ "member", "admin" ])
      expect(log.visibility).to eq("admin")
      expect(log.actor).to eq(actor)
    end
  end

  describe "schema" do
    it "has a last_accessed_at datetime column" do
      expect(Membership.columns_hash["last_accessed_at"].sql_type_metadata.type).to eq(:datetime)
    end

    it "has a composite index on [user_id, last_accessed_at]" do
      indexes = ActiveRecord::Base.connection.indexes("memberships")
      index = indexes.find { |i| i.columns == [ "user_id", "last_accessed_at" ] }
      expect(index).to be_present, "Expected composite index on (user_id, last_accessed_at)"
    end
  end

  describe "validations" do
    it "requires a user" do
      membership = build(:membership, user: nil)
      expect(membership).not_to be_valid
    end

    it "requires a workspace" do
      membership = build(:membership, workspace: nil)
      expect(membership).not_to be_valid
    end

    it "requires a role" do
      membership = build(:membership, role: nil)
      expect(membership).not_to be_valid
    end

    it "enforces one membership per user per workspace" do
      membership = create(:membership)
      duplicate = build(:membership, user: membership.user, workspace: membership.workspace)
      expect(duplicate).not_to be_valid
    end

    it "enforces uniqueness at the DATABASE level too (the concurrency backstop)" do
      membership = create(:membership)
      duplicate = build(:membership, user: membership.user, workspace: membership.workspace)

      # Bypass the app-level uniqueness validation on purpose. Under concurrent
      # admits, two transactions can both pass the model validation before
      # either commits — the unique index on (user_id, workspace_id) is what
      # actually prevents a duplicate membership row, making a double-claim of a
      # join-link/invitation token harmless. This guards against the index being
      # dropped and the invariant silently degrading to app-validation-only.
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "Discardable" do
    let(:membership) { create(:membership) }

    it "can be discarded" do
      membership.discard!
      expect(membership).to be_discarded
    end
  end

  describe "associations" do
    let(:membership) { create(:membership) }

    it "belongs to a user" do
      expect(membership.user).to be_a(User)
    end

    it "belongs to a workspace" do
      expect(membership.workspace).to be_a(Workspace)
    end

    it "belongs to a role" do
      expect(membership.role).to be_a(Role)
    end
  end

  describe "role change" do
    let(:membership) { create(:membership) }
    let(:admin_role) { Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" } }

    it "changes role" do
      membership.change_role!(admin_role)
      expect(membership.reload.role).to eq(admin_role)
    end
  end

  describe "deactivation" do
    let(:workspace) { create(:workspace) }
    let(:membership) { create(:membership, :owner, workspace: workspace) }

    it "deactivates a member" do
      create(:membership, :owner, workspace: workspace)
      membership.deactivate!
      expect(membership.reload).to be_discarded
    end

    it "prevents deactivating the last owner" do
      expect { membership.deactivate! }.to raise_error(ActiveRecord::RecordInvalid)
    end

    # Race-safety net for last-owner check. Pre-flight validate_not_last_owner!
    # runs against the workspace snapshot before discard; under concurrency two
    # owner-deactivations can both observe count==2 and proceed, leaving the
    # workspace ownerless. The post-discard invariant re-checks inside the
    # transaction (after our own discard), so a true race trips it.
    it "rolls back the deactivation if it would leave the workspace ownerless" do
      owner_a = create(:membership, :owner, workspace: workspace)
      owner_b = create(:membership, :owner, workspace: workspace)
      owner_a.discard!  # workspace now has 1 kept owner: owner_b

      # Bypass pre-flight to simulate a racer whose validate_not_last_owner!
      # passed against stale state.
      allow(owner_b).to receive(:validate_not_last_owner!)

      expect { owner_b.deactivate! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(owner_b.reload).not_to be_discarded
      expect(
        workspace.memberships.kept.joins(:role).where(roles: { slug: "owner" })
      ).to exist
    end
  end

  # A replayed DELETE — a stale tab, the back button, a scripted retry — reaches
  # MembersController#destroy with an already-discarded membership, because that
  # action resolves through the UNSCOPED association on purpose (the members
  # page shows removed people). Before this, Discardable#discard! moved
  # discarded_at t1 -> t2 unconditionally, so the removed member got a second
  # "was removed" row and a second email, and the audit trail grew a second
  # removal that never happened. The one-minute idempotency bucket absorbs a
  # rapid double-submit and nothing else.
  describe "deactivation idempotency" do
    let(:workspace) { create(:workspace) }
    let(:owner) { create(:user) }
    let(:membership) { create(:membership, workspace: workspace) }

    before do
      create(:membership, :owner, user: owner, workspace: workspace)
      membership
    end

    def removal_events
      Noticed::Event.where(type: "WorkspaceMemberRemovedNotifier")
    end

    def removal_audit_rows
      ActivityLog.where(trackable: membership, action: "membership.updated")
    end

    it "records one removal and one notification however many times it is called" do
      membership.deactivate!(removed_by: owner)
      # Past the notifier's dedup bucket, so a second dispatch would be a real
      # second event rather than a swallowed duplicate.
      travel_to(2.minutes.from_now) { membership.deactivate!(removed_by: owner) }

      expect(removal_events.count).to eq(1)
      expect(removal_audit_rows.count).to eq(1)
    end

    it "leaves the removal timestamp where the first call put it" do
      membership.deactivate!(removed_by: owner)
      first_stamp = membership.reload.discarded_at

      travel_to(2.minutes.from_now) { membership.deactivate!(removed_by: owner) }

      expect(membership.reload.discarded_at).to eq(first_stamp)
    end

    it "returns from the second call without writing an audit row" do
      membership.deactivate!(removed_by: owner)

      expect {
        travel_to(2.minutes.from_now) { membership.deactivate!(removed_by: owner) }
      }.not_to change { ActivityLog.count }
    end

    # Belt to the return's braces: any other path that re-stamps discarded_at on
    # an already-removed membership must not read as a fresh removal either.
    it "does not treat a re-discard as a new removal" do
      membership.deactivate!(removed_by: owner)

      expect {
        travel_to(2.minutes.from_now) { membership.discard! }
      }.not_to change { removal_events.count }
    end
  end

  describe "reactivation" do
    let(:membership) { create(:membership) }

    it "reactivates a deactivated member" do
      membership.discard!
      membership.reactivate!
      expect(membership.reload).not_to be_discarded
    end

    # Pins the deliberate admission-asymmetry documented on reactivate!: an
    # existing member of an ARCHIVED workspace can still be reactivated, even
    # though Workspace#admit blocks NEW admission into archived workspaces. If a
    # future refactor adds an admittable?/archived? guard to reactivate!, this
    # fails and forces that decision back into the open.
    it "reactivates a member even when the workspace is archived" do
      membership.discard!
      membership.workspace.archive!

      expect { membership.reactivate! }.not_to raise_error
      expect(membership.reload).not_to be_discarded
    end
  end

  describe "max_members enforcement" do
    it "prevents exceeding max_members" do
      # The workspace factory does not auto-create memberships.
      workspace = create(:workspace, max_members: 2)
      create(:membership, :owner, workspace: workspace)
      create(:membership, workspace: workspace)
      third = build(:membership, workspace: workspace)
      expect(third).not_to be_valid
      expect(third.errors[:base]).to be_present
    end

    it "acquires a lock on the workspace during capacity check" do
      workspace = create(:workspace, max_members: 5)
      membership = build(:membership, workspace: workspace)
      expect(workspace).to receive(:lock!).and_call_original
      membership.save
    end

    # Race-safety net: panel review flagged that the pre-flight validator's
    # workspace.lock! is a no-op across SQLite connections (per-connection
    # locking), so two concurrent invitation accepts could both pass count==N
    # and INSERT members N+1 + N+2. The post-create invariant runs inside the
    # create transaction with the row already inserted; SQLite's writer lock
    # serializes INSERTs, so by the time we COUNT we see the actual committed
    # state. Over-capacity → raise → roll back.
    it "rolls back the create when a racing transaction has filled capacity" do
      workspace = create(:workspace, max_members: 2)
      role = Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
      2.times { create(:membership, workspace: workspace) }

      user = create(:user)
      membership = Membership.new(workspace: workspace, user: user, role: role)

      # save!(validate: false) bypasses the pre-flight validator, simulating a
      # racing transaction whose validator passed against stale state. The
      # after_create invariant must catch the violation and roll back.
      expect { membership.save!(validate: false) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Membership.where(workspace: workspace, user: user)).not_to exist
    end
  end

  describe "scopes" do
    let(:workspace) { create(:workspace) }
    let!(:alice_membership) { create(:membership, :owner, workspace: workspace) }
    let!(:bob_membership) { create(:membership, :admin, workspace: workspace) }
    let!(:carol_membership) { create(:membership, workspace: workspace) }

    # Emails are pinned alongside names: .search also matches email_address,
    # and the factory's Faker email can randomly contain another member's
    # first name (e.g. "alice.baker@..."), making the exclusion assertions
    # flake (issue #467).
    before do
      alice_membership.user.update!(first_name: "Alice", last_name: "Anderson", email_address: "alice.anderson@example.test")
      bob_membership.user.update!(first_name: "Bob", last_name: "Baker", email_address: "bob.baker@example.test")
      carol_membership.user.update!(first_name: "Carol", last_name: "Clark", email_address: "carol.clark@example.test")
    end

    describe ".filter_by_role" do
      it "filters by role slug" do
        results = workspace.memberships.filter_by_role("owner")
        expect(results).to include(alice_membership)
        expect(results).not_to include(bob_membership)
      end

      it "returns all when role is blank" do
        expect(workspace.memberships.filter_by_role("")).to match_array(workspace.memberships)
        expect(workspace.memberships.filter_by_role(nil)).to match_array(workspace.memberships)
      end
    end

    describe ".filter_by_status" do
      before { carol_membership.discard! }

      it "filters active members" do
        results = workspace.memberships.filter_by_status("active")
        expect(results).to include(alice_membership, bob_membership)
        expect(results).not_to include(carol_membership)
      end

      it "filters deactivated members" do
        results = workspace.memberships.filter_by_status("deactivated")
        expect(results).to include(carol_membership)
        expect(results).not_to include(alice_membership)
      end

      it "returns all when status is blank" do
        expect(workspace.memberships.filter_by_status("")).to match_array(workspace.memberships)
      end
    end
  end

  # G (SEC-1 follow-up): membership.created previously carried empty metadata —
  # no role, no granter. The grant itself is the privilege event.
  describe "creation audit metadata" do
    it "records the granted role slug" do
      membership = create(:membership, :owner)

      entry = ActivityLog.where(action: "membership.created", trackable: membership).last
      expect(entry).to be_present
      expect(entry.metadata["role"]).to eq("owner")
    end
  end
end
