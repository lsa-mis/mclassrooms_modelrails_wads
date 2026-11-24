require "rails_helper"

# Workspace::Admission's examples. A concern trait is not instantiated, so its
# examples describe the model; this file is scoped by directory to the trait.
RSpec.describe Workspace, type: :model do
  describe "#open_join?" do
    before { permit_open_join_links }

    it "is true for an org workspace with join_policy 'open_link' when instance permits it" do
      workspace = build(:workspace, :open_link)
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
    before { permit_open_join_links }

    it "is true when the join policy is open and the workspace is admittable" do
      workspace = create(:workspace, :open_link)
      expect(workspace.accepting_open_joins?).to be(true)
    end

    it "is false when the join policy is not open" do
      workspace = create(:workspace, :open_link)
      workspace.update!(join_policy: "invite")
      expect(workspace.accepting_open_joins?).to be(false)
    end

    it "is false when the workspace is not admittable (archived/suspended)" do
      workspace = create(:workspace, :open_link)
      workspace.archive!
      expect(workspace.accepting_open_joins?).to be(false)
    end
  end

  describe "#admit" do
    def admit_workspace
      create(:workspace, max_members: 3, personal: false)
    end

    it "creates a membership for a new user at the specified role" do
      workspace = admit_workspace
      user = create(:user)
      member_role = Role.system_default!("member")

      expect {
        workspace.admit(user, role: member_role)
      }.to change(workspace.memberships, :count).by(1)

      expect(workspace.memberships.find_by!(user: user).role).to eq(member_role)
    end

    # Joining a workspace is onboarding under every preset: the first-run
    # wizard exists for a user who has nowhere to go, and under :none an
    # unstamped invitee is funnelled into a step that refuses a Member.
    it "marks the admitted user onboarded" do
      workspace = admit_workspace
      user = create(:user)
      member_role = Role.system_default!("member")

      expect {
        workspace.admit(user, role: member_role)
      }.to change { user.reload.onboarded? }.from(false).to(true)
    end

    it "does not stamp a user the workspace refuses" do
      workspace = admit_workspace
      user = create(:user)
      member_role = Role.system_default!("member")
      workspace.suspend!

      expect { workspace.admit(user, role: member_role) }.to raise_error(Workspace::NotAdmittableError)
      expect(user.reload.onboarded?).to be(false)
    end

    it "reactivates a discarded membership without overwriting its role" do
      workspace = admit_workspace
      user = create(:user)
      member_role = Role.system_default!("member")
      other_owner = create(:user)
      create(:membership, :owner, user: other_owner, workspace: workspace)
      discarded = create(:membership, user: user, workspace: workspace)
      discarded.deactivate!

      expect {
        workspace.admit(user, role: member_role)
      }.not_to change(workspace.memberships, :count)

      expect(discarded.reload).not_to be_discarded
    end

    it "reactivates a discarded membership with on_existing: :adopt (no granted_by rewrite, same as :raise)" do
      workspace = admit_workspace
      user = create(:user)
      member_role = Role.system_default!("member")
      other_owner = create(:user)
      create(:membership, :owner, user: other_owner, workspace: workspace)
      discarded = create(:membership, user: user, workspace: workspace)
      discarded.deactivate!

      result = nil
      expect {
        result = workspace.admit(user, role: member_role, granted_by: other_owner, on_existing: :adopt)
      }.not_to change(workspace.memberships, :count)

      expect(result).to eq(discarded)
      expect(discarded.reload).not_to be_discarded
      # Reactivation keeps the original grant's provenance; admit's granted_by
      # lives on its own copy of the row (notifier actor exclusion), not a rewrite.
      expect(discarded.granted_by).to be_nil
    end

    it "raises AtCapacity when the workspace is at capacity" do
      workspace = admit_workspace
      user = create(:user)
      member_role = Role.system_default!("member")
      workspace.update!(max_members: 1)
      create(:membership, :owner, user: create(:user), workspace: workspace)

      expect {
        workspace.admit(user, role: member_role)
      }.to raise_error(Workspace::AtCapacity)
    end

    context "when user is already a kept member" do
      def kept_member_of(workspace, user)
        create(:membership, user: user, workspace: workspace)
      end

      it "raises AlreadyMember under :personal (duplicate-accept error)" do
        workspace = admit_workspace
        user = create(:user)
        kept_member_of(workspace, user)
        owner_role = Role.system_default!("owner")

        expect {
          workspace.admit(user, role: owner_role)
        }.to raise_error(Workspace::AlreadyMember)
      end

      it "adopts the existing membership untouched with on_existing: :adopt" do
        workspace = admit_workspace
        user = create(:user)
        existing = kept_member_of(workspace, user)
        owner_role = Role.system_default!("owner")
        member_role = Role.system_default!("member")

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
        def stub_shared_posture(workspace)
          allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
          allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
        end

        it "updates the role when it differs (placeholder reconciliation)" do
          workspace = admit_workspace
          user = create(:user)
          kept_member_of(workspace, user)
          stub_shared_posture(workspace)
          owner_role = Role.system_default!("owner")

          expect {
            workspace.admit(user, role: owner_role)
          }.not_to raise_error

          expect(workspace.memberships.find_by!(user: user).role).to eq(owner_role)
        end

        it "no-ops when the role matches" do
          workspace = admit_workspace
          user = create(:user)
          kept_member_of(workspace, user)
          stub_shared_posture(workspace)
          member_role = Role.system_default!("member")

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
      # Users are created before `shared?` is stubbed: the stub must not reach
      # User#onboard_workspace, which reads TenancyConfig.onboarding.
      def two_owners_of(workspace)
        owner_a = create(:user)
        owner_b = create(:user)
        create(:membership, :owner, user: owner_a, workspace: workspace)
        create(:membership, :owner, user: owner_b, workspace: workspace)
        allow(TenancyConfig).to receive(:shared?).and_return(true)
        Noticed::Notification.delete_all
        Noticed::Event.delete_all
        [ owner_a, owner_b ]
      end

      def recipients_of(notifier)
        Noticed::Notification.where(type: "#{notifier}::Notification")
          .includes(:recipient).map(&:recipient)
      end

      it "keeps the granter out of the member-added fan-out" do
        workspace = admit_workspace
        user = create(:user)
        owner_a, owner_b = two_owners_of(workspace)
        member_role = Role.system_default!("member")
        owner_role = Role.system_default!("owner")

        ActiveRecord::Base.transaction do
          workspace.memberships.create!(user: user, role: member_role, self_join: :onboarding)
          workspace.admit(user, role: owner_role, granted_by: owner_a)
        end

        expect(recipients_of(WorkspaceMemberAddedNotifier)).to contain_exactly(user, owner_b)
      end

      it "keeps a chosen self-join's joiner out of the fan-out and still orients them" do
        workspace = admit_workspace
        user = create(:user)
        owner_a, owner_b = two_owners_of(workspace)
        member_role = Role.system_default!("member")
        owner_role = Role.system_default!("owner")

        ActiveRecord::Base.transaction do
          workspace.memberships.create!(user: user, role: member_role, self_join: :onboarding)
          workspace.admit(user, role: owner_role, self_join: true)
        end

        expect(recipients_of(WorkspaceMemberAddedNotifier)).to contain_exactly(owner_a, owner_b)
        expect(recipients_of(WorkspaceJoinedNotifier)).to contain_exactly(user)
      end

      it "carries the granter onto the instance on_existing: :adopt returns" do
        workspace = admit_workspace
        user = create(:user)
        owner_a, = two_owners_of(workspace)
        member_role = Role.system_default!("member")
        create(:membership, user: user, workspace: workspace)

        result = workspace.admit(user, role: member_role, granted_by: owner_a, on_existing: :adopt)

        expect(result.granted_by).to eq(owner_a)
      end

      it "carries the self-join marker onto the instance on_existing: :adopt returns" do
        workspace = admit_workspace
        user = create(:user)
        two_owners_of(workspace)
        member_role = Role.system_default!("member")
        create(:membership, user: user, workspace: workspace)

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
      create(:membership, :deactivated, workspace: workspace)

      expect(workspace.at_capacity?).to be false
    end
  end

  # Admittability (kept, not archived, not suspended) gates every admission;
  # these moved from workspace_lifecycle_spec.rb (#1003).
  describe "#admittable?" do
    it "is true only when active (kept, not archived, not suspended)" do
      workspace = create(:workspace)
      expect(workspace.admittable?).to be(true)
    end

    it "is false when archived" do
      workspace = create(:workspace)
      workspace.archive!
      expect(workspace.admittable?).to be(false)
    end

    it "is false when suspended" do
      workspace = create(:workspace)
      workspace.suspend!
      expect(workspace.admittable?).to be(false)
    end

    it "is false when discarded" do
      workspace = create(:workspace)
      workspace.discard!
      expect(workspace.admittable?).to be(false)
    end
  end

  describe "#admit admittability guard" do
    it "raises NotAdmittableError when the workspace is archived" do
      workspace = create(:workspace)
      joiner = create(:user)
      role = Role.system_default!("member")
      workspace.archive!
      expect { workspace.admit(joiner, role: role) }.to raise_error(Workspace::NotAdmittableError)
      expect(workspace.reload.memberships.where(user: joiner)).to be_empty
    end

    it "raises NotAdmittableError when the workspace is suspended" do
      workspace = create(:workspace)
      joiner = create(:user)
      role = Role.system_default!("member")
      workspace.suspend!
      expect { workspace.admit(joiner, role: role) }.to raise_error(Workspace::NotAdmittableError)
    end

    it "admits normally into an active workspace" do
      workspace = create(:workspace)
      joiner = create(:user)
      role = Role.system_default!("member")
      expect { workspace.admit(joiner, role: role) }.to change { workspace.memberships.kept.count }.by(1)
    end
  end
end
