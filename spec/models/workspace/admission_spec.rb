require "rails_helper"

# Workspace::Admission's examples. A concern trait is not instantiated, so its
# examples describe the model; this file is scoped by directory to the trait.
RSpec.describe Workspace, type: :model do
  describe "#open_join?" do
    before { allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link]) }

    it "is true for an org workspace with join_policy 'open_link' when instance permits it" do
      workspace = build(:workspace, join_policy: "open_link", personal: false)
      expect(workspace).to be_open_join
    end

    it "is false on a personal workspace, regardless of policy (hard guard)" do
      # Build without validation so we can simulate a malformed row reaching the predicate.
      workspace = build(:workspace, personal: true)
      workspace.join_policy = "open_link"
      expect(workspace).not_to be_open_join
    end

    it "is false when the instance allowlist excludes :open_link" do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite])
      workspace = build(:workspace, personal: false)
      workspace.join_policy = "open_link"
      expect(workspace).not_to be_open_join
    end

    it "is false for invite policy" do
      workspace = build(:workspace, join_policy: "invite", personal: false)
      expect(workspace).not_to be_open_join
    end
  end

  # Single membership-grant entry point — extracted from Invitation so the
  # open-link self-join path can share the same lock + capacity + discarded-
  # reactivation + role-reconciliation logic.
  describe "#accepting_open_joins?" do
    let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }

    before do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    end

    it "is true when the join policy is open and the workspace is admittable" do
      expect(workspace.accepting_open_joins?).to be(true)
    end

    it "is false when the join policy is not open" do
      workspace.update!(join_policy: "invite")
      expect(workspace.accepting_open_joins?).to be(false)
    end

    it "is false when the workspace is not admittable (archived/suspended)" do
      workspace.archive!
      expect(workspace.accepting_open_joins?).to be(false)
    end
  end

  describe "#admit" do
    let(:workspace) { create(:workspace, max_members: 3, personal: false) }
    let(:user) { create(:user) }

    let!(:owner_role) {
      Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r|
        r.name = "Owner"
        r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
      }
    }
    let!(:member_role) {
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r|
        r.name = "Member"
        r.permissions = { manage_projects: true }
      }
    }

    it "creates a membership for a new user at the specified role" do
      expect {
        workspace.admit(user, role: member_role)
      }.to change(workspace.memberships, :count).by(1)

      expect(workspace.memberships.find_by!(user: user).role).to eq(member_role)
    end

    it "reactivates a discarded membership without overwriting its role" do
      # Seed the workspace with an Owner so deactivating doesn't violate
      # "must keep at least one owner" rules — and create a regular member
      # to deactivate as the test subject.
      other_owner = create(:user)
      workspace.memberships.create!(user: other_owner, role: owner_role)
      discarded = workspace.memberships.create!(user: user, role: member_role)
      discarded.deactivate!

      expect {
        workspace.admit(user, role: member_role)
      }.not_to change(workspace.memberships, :count)

      expect(discarded.reload).not_to be_discarded
    end

    it "reactivates a discarded membership with on_existing: :adopt (no granted_by rewrite, same as :raise)" do
      other_owner = create(:user)
      workspace.memberships.create!(user: other_owner, role: owner_role)
      discarded = workspace.memberships.create!(user: user, role: member_role)
      discarded.deactivate!

      result = nil
      expect {
        result = workspace.admit(user, role: member_role, granted_by: other_owner, on_existing: :adopt)
      }.not_to change(workspace.memberships, :count)

      expect(result).to eq(discarded)
      expect(discarded.reload).not_to be_discarded
      # Reactivation preserves the original grant's provenance: no new
      # `membership.created` audit row, and admit never mutates the caller's
      # instance. The granted_by admit sets on its OWN copy of the row is
      # transient notifier provenance (actor exclusion), not a rewrite.
      expect(discarded.granted_by).to be_nil
    end

    it "raises AtCapacity when the workspace is at capacity" do
      # Fill the workspace to max_members.
      workspace.update!(max_members: 1)
      workspace.memberships.create!(user: create(:user), role: owner_role)

      expect {
        workspace.admit(user, role: member_role)
      }.to raise_error(Workspace::AtCapacity)
    end

    context "when user is already a kept member" do
      before { workspace.memberships.create!(user: user, role: member_role) }

      it "raises AlreadyMember under :personal (duplicate-accept error)" do
        expect {
          workspace.admit(user, role: owner_role)
        }.to raise_error(Workspace::AlreadyMember)
      end

      it "adopts the existing membership untouched with on_existing: :adopt" do
        existing = workspace.memberships.find_by!(user: user)

        result = nil
        expect {
          result = workspace.admit(user, role: owner_role, on_existing: :adopt)
        }.not_to change(workspace.memberships, :count)

        expect(result).to eq(existing)
        # Adopt tolerates the member as-is: no role overwrite, even though the
        # admit call asked for a different role.
        expect(existing.reload.role).to eq(member_role)
      end

      context "under :shared posture" do
        before do
          allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
          allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
        end

        it "updates the role when it differs (placeholder reconciliation)" do
          expect {
            workspace.admit(user, role: owner_role)
          }.not_to raise_error

          expect(workspace.memberships.find_by!(user: user).role).to eq(owner_role)
        end

        it "no-ops when the role matches" do
          expect { workspace.admit(user, role: member_role) }.not_to raise_error
        end
      end
    end

    # Rails runs a row's commit callbacks on the LAST instance of it saved in
    # the transaction (run_commit_callbacks_on_first_saved_instances_in_transaction
    # is false), so the reconciling instance — not the one that did the INSERT —
    # is what the actor rule reads. The interleaving is real, not theoretical:
    # Signupable#commit_signup_atomically runs `user.save!` (→ User#onboard_workspace
    # → the :shared placeholder membership) and PendingClaims#claim! (→
    # Invitation#accept! → #admit) inside ONE transaction.
    context "when a second instance of the row saves in the same transaction" do
      # NOTE: users are created before `shared?` is stubbed on purpose — the
      # stub is scoped to admit's reconcile branch and must not reach
      # User#onboard_workspace, which reads TenancyConfig.onboarding.
      let!(:owner_a) { create(:user) }
      let!(:owner_b) { create(:user) }
      let!(:owner_a_membership) { workspace.memberships.create!(user: owner_a, role: owner_role) }
      let!(:owner_b_membership) { workspace.memberships.create!(user: owner_b, role: owner_role) }

      before do
        allow(TenancyConfig).to receive(:shared?).and_return(true)
        Noticed::Notification.delete_all
        Noticed::Event.delete_all
      end

      def recipients_of(notifier)
        Noticed::Notification.where(type: "#{notifier}::Notification").map(&:recipient)
      end

      it "keeps the granter out of the member-added fan-out" do
        ActiveRecord::Base.transaction do
          workspace.memberships.create!(user: user, role: member_role, self_join: :onboarding)
          workspace.admit(user, role: owner_role, granted_by: owner_a)
        end

        expect(recipients_of(WorkspaceMemberAddedNotifier)).to contain_exactly(user, owner_b)
      end

      it "keeps a chosen self-join's joiner out of the fan-out and still orients them" do
        ActiveRecord::Base.transaction do
          workspace.memberships.create!(user: user, role: member_role, self_join: :onboarding)
          workspace.admit(user, role: owner_role, self_join: true)
        end

        expect(recipients_of(WorkspaceMemberAddedNotifier)).to contain_exactly(owner_a, owner_b)
        expect(recipients_of(WorkspaceJoinedNotifier)).to contain_exactly(user)
      end

      it "carries the granter onto the instance on_existing: :adopt returns" do
        workspace.memberships.create!(user: user, role: member_role)

        result = workspace.admit(user, role: member_role, granted_by: owner_a, on_existing: :adopt)

        expect(result.granted_by).to eq(owner_a)
      end

      it "carries the self-join marker onto the instance on_existing: :adopt returns" do
        workspace.memberships.create!(user: user, role: member_role)

        result = workspace.admit(user, role: member_role, self_join: true, on_existing: :adopt)

        expect(result.self_join).to be true
      end
    end
  end

  describe "#at_capacity?" do
    it "is true when kept memberships have reached max_members" do
      workspace = create(:workspace, max_members: 1)
      create(:membership, workspace: workspace)

      expect(workspace.at_capacity?).to be true
    end

    it "is false below the limit" do
      workspace = create(:workspace, max_members: 2)
      create(:membership, workspace: workspace)

      expect(workspace.at_capacity?).to be false
    end

    it "does not count discarded memberships" do
      workspace = create(:workspace, max_members: 1)
      create(:membership, workspace: workspace).discard!

      expect(workspace.at_capacity?).to be false
    end
  end

  # Admittability (kept, not archived, not suspended) gates every admission;
  # these moved from workspace_lifecycle_spec.rb (#1003).
  describe "#admittable?" do
    let(:workspace) { create(:workspace) }

    it "is true only when active (kept, not archived, not suspended)" do
      expect(workspace.admittable?).to be(true)
    end

    it "is false when archived" do
      workspace.archive!
      expect(workspace.admittable?).to be(false)
    end

    it "is false when suspended" do
      workspace.suspend!
      expect(workspace.admittable?).to be(false)
    end

    it "is false when discarded" do
      workspace.discard!
      expect(workspace.admittable?).to be(false)
    end
  end

  describe "#admit admittability guard" do
    let(:workspace) { create(:workspace) }
    let(:role) { Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" } }
    let(:joiner) { create(:user) }

    it "raises NotAdmittableError when the workspace is archived" do
      workspace.archive!
      expect { workspace.admit(joiner, role: role) }.to raise_error(Workspace::NotAdmittableError)
      expect(workspace.reload.memberships.where(user: joiner)).to be_empty
    end

    it "raises NotAdmittableError when the workspace is suspended" do
      workspace.suspend!
      expect { workspace.admit(joiner, role: role) }.to raise_error(Workspace::NotAdmittableError)
    end

    it "admits normally into an active workspace" do
      expect { workspace.admit(joiner, role: role) }.to change { workspace.memberships.kept.count }.by(1)
    end
  end
end
