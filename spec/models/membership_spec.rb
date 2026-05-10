require "rails_helper"

RSpec.describe Membership, type: :model do
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

  describe "reactivation" do
    let(:membership) { create(:membership) }

    it "reactivates a deactivated member" do
      membership.discard!
      membership.reactivate!
      expect(membership.reload).not_to be_discarded
    end
  end

  describe "max_members enforcement" do
    it "prevents exceeding max_members" do
      # Create a workspace with max_members: 2
      # The workspace factory does not auto-create memberships,
      # so we manually create 2 memberships then try a third.
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

    before do
      alice_membership.user.update!(first_name: "Alice", last_name: "Anderson")
      bob_membership.user.update!(first_name: "Bob", last_name: "Baker")
      carol_membership.user.update!(first_name: "Carol", last_name: "Clark")
    end

    describe ".search" do
      it "finds by first name" do
        results = workspace.memberships.search("Alice")
        expect(results).to include(alice_membership)
        expect(results).not_to include(bob_membership)
      end

      it "finds by last name" do
        results = workspace.memberships.search("Baker")
        expect(results).to include(bob_membership)
      end

      it "finds by email" do
        results = workspace.memberships.search(alice_membership.user.email_address)
        expect(results).to include(alice_membership)
      end

      it "is case-insensitive" do
        results = workspace.memberships.search("alice")
        expect(results).to include(alice_membership)
      end

      it "returns all when query is blank" do
        expect(workspace.memberships.search("")).to match_array(workspace.memberships)
        expect(workspace.memberships.search(nil)).to match_array(workspace.memberships)
      end
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

    describe ".sorted_by" do
      it "sorts by name ascending" do
        results = workspace.memberships.includes(:user).sorted_by("name", "asc")
        names = results.map { |m| m.user.first_name }
        expect(names).to eq(%w[Alice Bob Carol])
      end

      it "sorts by name descending" do
        results = workspace.memberships.includes(:user).sorted_by("name", "desc")
        names = results.map { |m| m.user.first_name }
        expect(names).to eq(%w[Carol Bob Alice])
      end

      it "sorts by role" do
        results = workspace.memberships.includes(:role).sorted_by("role", "asc")
        expect(results).to be_present
      end

      it "defaults to created_at desc for unknown columns" do
        results = workspace.memberships.sorted_by("unknown", "asc")
        expect(results).to eq(workspace.memberships.order(created_at: :desc))
      end
    end
  end

  describe "ownership transfer" do
    let(:workspace) { create(:workspace) }
    let(:owner_membership) { create(:membership, :owner, workspace: workspace) }
    let(:target_membership) { create(:membership, workspace: workspace) }

    it "promotes the target to owner" do
      owner_role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" }
      owner_membership.transfer_ownership_to!(target_membership)
      expect(target_membership.reload.role).to eq(owner_role)
    end

    it "demotes the current owner to admin" do
      admin_role = Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" }
      owner_membership.transfer_ownership_to!(target_membership)
      expect(owner_membership.reload.role).to eq(admin_role)
    end

    # Race-safety: panel review flagged that two concurrent transfers from
    # the same owner could leave the workspace with two owners (both target
    # promotions succeed, demote-self is idempotent). Demote must be an
    # atomic conditional update guarded by current role; if a racer already
    # demoted us, abort *before* promoting target.
    it "raises and leaves target unpromoted if current role is no longer owner" do
      admin_role = Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" }
      # Out-of-band demote simulates a racing transfer that already won;
      # stub reload so the in-memory role stays "owner" (modelling a stale
      # snapshot read on a different connection).
      Membership.where(id: owner_membership.id).update_all(role_id: admin_role.id)
      allow(owner_membership).to receive(:reload) { owner_membership }

      expect {
        owner_membership.transfer_ownership_to!(target_membership)
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(target_membership.reload.role.slug).not_to eq("owner")
    end
  end

  # Locks in the self-exclusion semantic of the predicate that gates the
  # WorkspaceMemberAddedNotifier `after_create_commit` callback. The predicate
  # name (`workspace_has_other_owners?`) must reflect that we're asking about
  # owners *other than this membership* — without that exclusion, the very
  # first owner being seeded for a fresh workspace would self-trigger a
  # "new member joined" notification with itself as the audience.
  #
  # Predicate is private (matches Rails conventions for callback gates); we
  # exercise it via `send` rather than expose the method publicly just for
  # tests.
  describe "#workspace_has_other_owners? (self-exclusion semantic)" do
    let(:workspace) { create(:workspace) }

    it "returns false when this is the only owner-role membership in the workspace" do
      sole_owner = create(:membership, :owner, workspace: workspace)
      expect(sole_owner.send(:workspace_has_other_owners?)).to be false
    end

    it "returns true when another owner-role membership exists in the workspace" do
      first_owner = create(:membership, :owner, workspace: workspace)
      create(:membership, :owner, workspace: workspace)
      expect(first_owner.send(:workspace_has_other_owners?)).to be true
    end

    it "returns true for a non-owner membership when another owner-role membership exists in the workspace" do
      # The predicate is a workspace-scoped question — "are there other
      # owners in this workspace?" — not "is THIS membership not the lone
      # owner?". A non-owner member added to a workspace that already has
      # an owner returns true (the gate fires the notifier).
      create(:membership, :owner, workspace: workspace)
      member_membership = create(:membership, workspace: workspace)
      expect(member_membership.send(:workspace_has_other_owners?)).to be true
    end

    it "returns false when no other owner exists even with an admin sibling" do
      sole_owner = create(:membership, :owner, workspace: workspace)
      create(:membership, :admin, workspace: workspace)
      expect(sole_owner.send(:workspace_has_other_owners?)).to be false
    end

    it "ignores discarded owner memberships" do
      first_owner = create(:membership, :owner, workspace: workspace)
      second_owner = create(:membership, :owner, workspace: workspace)
      second_owner.discard!
      expect(first_owner.send(:workspace_has_other_owners?)).to be false
    end

    it "ignores owners from other workspaces" do
      sole_in_target = create(:membership, :owner, workspace: workspace)
      other_workspace = create(:workspace)
      create(:membership, :owner, workspace: other_workspace)
      expect(sole_in_target.send(:workspace_has_other_owners?)).to be false
    end
  end
end
