require "rails_helper"

# Membership::Ownership's examples. A concern trait is not instantiated, so its
# examples describe the model; this file is scoped by directory to the trait.
RSpec.describe Membership, type: :model do
  describe "#owner?" do
    it "is true when the role is the owner role" do
      expect(build(:membership, :owner).owner?).to be true
    end

    it "is false for non-owner roles" do
      expect(build(:membership).owner?).to be false
    end

    it "answers role identity only — a discarded owner membership is still owner?" do
      membership = create(:membership, :owner)
      membership.discard!

      expect(membership.owner?).to be true
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

    # G (SEC-1 follow-up): the demote is a callback-skipping CAS update_all
    # (race-safety, by design) — which also skipped Trackable. A privilege
    # demotion must still reach the audit trail, explicitly.
    it "audits the demotion at admin visibility despite the callback-skipping CAS" do
      owner_membership.transfer_ownership_to!(target_membership)

      entry = ActivityLog.where(action: "membership.updated", trackable: owner_membership).last
      expect(entry).to be_present
      expect(entry.visibility).to eq("admin")
      expect(entry.metadata.dig("changes", "role")).to eq([ "owner", "admin" ])
    end

    # Ruling 9 (#1008): a model reads Current only inside the audit concern. The
    # demotion's actor is the owner stepping down — the membership's own user —
    # which is exact from the console and a job as well as from the controller.
    it "attributes the demotion to the owner stepping down, with no Current.user set" do
      Current.session = nil # Current.user delegates to the session; none here, as in a job
      owner_membership.transfer_ownership_to!(target_membership)

      entry = ActivityLog.where(action: "membership.updated", trackable: owner_membership).last
      expect(entry.actor).to eq(owner_membership.user)
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

  # The one owner query. Its self-exclusion is the contract every caller
  # leans on: the last-owner guards ask "is there an owner besides me?", and
  # the member-added announcement gate uses it so the very first owner seeded
  # for a fresh workspace does not announce itself to itself.
  describe ".other_kept_owners" do
    let(:workspace) { create(:workspace) }

    it "is empty when the excluded membership is the only owner" do
      sole_owner = create(:membership, :owner, workspace: workspace)

      expect(Membership.other_kept_owners(workspace.id, excluding: sole_owner.id)).to be_empty
    end

    it "returns the kept owner-role memberships in the workspace other than the excluded one" do
      first_owner = create(:membership, :owner, workspace: workspace)
      second_owner = create(:membership, :owner, workspace: workspace)

      expect(Membership.other_kept_owners(workspace.id, excluding: first_owner.id))
        .to contain_exactly(second_owner)
    end

    it "answers for a non-owner membership too: the question is workspace-scoped, not about the asker" do
      owner = create(:membership, :owner, workspace: workspace)
      member = create(:membership, workspace: workspace)

      expect(Membership.other_kept_owners(workspace.id, excluding: member.id)).to contain_exactly(owner)
    end

    it "excludes discarded owners, non-owner roles, and owners of other workspaces" do
      owner = create(:membership, :owner, workspace: workspace)
      create(:membership, :owner, workspace: workspace).discard!
      create(:membership, :admin, workspace: workspace)
      create(:membership, :owner, workspace: create(:workspace))

      expect(Membership.other_kept_owners(workspace.id, excluding: owner.id)).to be_empty
    end
  end
end
