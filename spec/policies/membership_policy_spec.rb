require "rails_helper"

RSpec.describe MembershipPolicy do
  def current_workspace
    create(:workspace).tap { |workspace| Current.workspace = workspace }
  end

  def user_in(workspace, *traits)
    create(:user).tap { |user| create(:membership, *traits, user: user, workspace: workspace) }
  end

  describe "for owner" do
    it "allows index" do
      workspace = current_workspace
      user = user_in(workspace, :owner)
      other_membership = create(:membership, workspace: workspace)
      expect(described_class.new(user, other_membership).index?).to be true
    end

    it "allows update" do
      workspace = current_workspace
      user = user_in(workspace, :owner)
      other_membership = create(:membership, workspace: workspace)
      expect(described_class.new(user, other_membership).update?).to be true
    end

    it "allows destroy" do
      workspace = current_workspace
      user = user_in(workspace, :owner)
      other_membership = create(:membership, workspace: workspace)
      expect(described_class.new(user, other_membership).destroy?).to be true
    end

    it "denies destroying self" do
      workspace = current_workspace
      user = user_in(workspace, :owner)
      own_membership = workspace.memberships.kept.find_by(user: user)
      expect(described_class.new(user, own_membership).destroy?).to be false
    end

    it "allows reactivate" do
      workspace = current_workspace
      user = user_in(workspace, :owner)
      other_membership = create(:membership, workspace: workspace)
      expect(described_class.new(user, other_membership).reactivate?).to be true
    end

    it "allows transfer_ownership" do
      workspace = current_workspace
      user = user_in(workspace, :owner)
      other_membership = create(:membership, workspace: workspace)
      expect(described_class.new(user, other_membership).transfer_ownership?).to be true
    end
  end

  describe "for member" do
    it "allows index" do
      workspace = current_workspace
      user = user_in(workspace)
      other_membership = create(:membership, workspace: workspace)
      expect(described_class.new(user, other_membership).index?).to be true
    end

    it "denies update" do
      workspace = current_workspace
      user = user_in(workspace)
      other_membership = create(:membership, workspace: workspace)
      expect(described_class.new(user, other_membership).update?).to be false
    end

    it "denies destroy" do
      workspace = current_workspace
      user = user_in(workspace)
      other_membership = create(:membership, workspace: workspace)
      expect(described_class.new(user, other_membership).destroy?).to be false
    end

    it "denies transfer_ownership" do
      workspace = current_workspace
      user = user_in(workspace)
      other_membership = create(:membership, workspace: workspace)
      expect(described_class.new(user, other_membership).transfer_ownership?).to be false
    end
  end

  describe "#destroy? — admin deactivates someone else" do
    it "permits admin to deactivate another member" do
      workspace = current_workspace
      user = user_in(workspace, :admin)
      record = create(:membership, user: create(:user), workspace: workspace)
      expect(described_class.new(user, record).destroy?).to be(true)
    end

    it "denies when the workspace is discarded" do
      workspace = current_workspace
      user = user_in(workspace, :admin)
      record = create(:membership, user: create(:user), workspace: workspace)
      workspace.discard!
      record.reload
      expect(described_class.new(user, record).destroy?).to be(false)
    end
  end

  describe "#destroy? — user leaves own membership" do
    def leaver_with_other_owner(workspace)
      user = create(:user)
      other_owner = create(:membership, :owner, user: create(:user), workspace: workspace)
      [ user, create(:membership, user: user, workspace: workspace), other_owner ]
    end

    it "permits leaving when not last owner and not personal workspace" do
      workspace = current_workspace
      user, record, = leaver_with_other_owner(workspace)
      expect(described_class.new(user, record).destroy?).to be(true)
    end

    it "denies leaving the user's personal workspace" do
      workspace = current_workspace
      user, record, = leaver_with_other_owner(workspace)
      user.update!(personal_workspace_id: workspace.id)
      expect(described_class.new(user, record).destroy?).to be(false)
    end

    it "permits an owner leaving while another owner remains" do
      workspace = current_workspace
      user, record, = leaver_with_other_owner(workspace)
      record.update!(role: Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" })
      expect(described_class.new(user, record).destroy?).to be(true)
    end

    it "denies leaving when the user is the last owner" do
      workspace = current_workspace
      user, record, owner_membership_other = leaver_with_other_owner(workspace)
      owner_membership_other.update!(discarded_at: Time.current)
      record.update!(role: Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" })
      expect(described_class.new(user, record).destroy?).to be(false)
    end

    it "denies when the workspace is discarded" do
      workspace = current_workspace
      user, record, = leaver_with_other_owner(workspace)
      workspace.discard!
      record.reload
      expect(described_class.new(user, record).destroy?).to be(false)
    end
  end

  describe "#destroy? — non-member" do
    it "denies non-members" do
      workspace = current_workspace
      record = create(:membership, user: create(:user), workspace: workspace)
      actor = create(:user)
      expect(described_class.new(actor, record).destroy?).to be(false)
    end
  end

  # SEC-1: privilege-elevation guard. An actor may grant a role only if they
  # already hold every permission it confers.
  describe "#may_grant?" do
    context "actor is owner" do
      it "may grant owner" do
        workspace = current_workspace
        user = user_in(workspace, :owner)
        policy = described_class.new(user, create(:membership, workspace: workspace))
        expect(policy.may_grant?(Role.system_default!("owner"))).to be(true)
      end

      it "may grant admin" do
        workspace = current_workspace
        user = user_in(workspace, :owner)
        policy = described_class.new(user, create(:membership, workspace: workspace))
        expect(policy.may_grant?(Role.system_default!("admin"))).to be(true)
      end
    end

    context "actor is admin" do
      it "may NOT grant owner (no manage_workspace)" do
        workspace = current_workspace
        user = user_in(workspace, :admin)
        policy = described_class.new(user, create(:membership, workspace: workspace))
        expect(policy.may_grant?(Role.system_default!("owner"))).to be(false)
      end

      it "may NOT grant a custom role that confers a permission it lacks" do
        workspace = current_workspace
        user = user_in(workspace, :admin)
        policy = described_class.new(user, create(:membership, workspace: workspace))
        superadmin = create(:role, workspace: workspace, name: "Superadmin", slug: "superadmin",
                                   permissions: { "manage_workspace" => true })
        expect(policy.may_grant?(superadmin)).to be(false)
      end

      it "may grant admin (lateral)" do
        workspace = current_workspace
        user = user_in(workspace, :admin)
        policy = described_class.new(user, create(:membership, workspace: workspace))
        expect(policy.may_grant?(Role.system_default!("admin"))).to be(true)
      end

      it "may grant member" do
        workspace = current_workspace
        user = user_in(workspace, :admin)
        policy = described_class.new(user, create(:membership, workspace: workspace))
        expect(policy.may_grant?(Role.system_default!("member"))).to be(true)
      end

      it "may grant viewer" do
        workspace = current_workspace
        user = user_in(workspace, :admin)
        policy = described_class.new(user, create(:membership, workspace: workspace))
        expect(policy.may_grant?(Role.system_default!("viewer"))).to be(true)
      end
    end

    context "actor is member" do
      it "may NOT grant admin" do
        workspace = current_workspace
        user = user_in(workspace)
        policy = described_class.new(user, create(:membership, workspace: workspace))
        expect(policy.may_grant?(Role.system_default!("admin"))).to be(false)
      end

      it "may grant viewer (member holds no permissions viewer requires)" do
        workspace = current_workspace
        user = user_in(workspace)
        policy = described_class.new(user, create(:membership, workspace: workspace))
        expect(policy.may_grant?(Role.system_default!("viewer"))).to be(true)
      end
    end

    context "actor has no membership in the current workspace" do
      it "may grant nothing, not even viewer" do
        workspace = current_workspace
        policy = described_class.new(create(:user), create(:membership, workspace: workspace))
        expect(policy.may_grant?(Role.system_default!("viewer"))).to be(false)
        expect(policy.may_grant?(Role.system_default!("admin"))).to be(false)
      end
    end

    context "actor is member; custom role explicitly DISABLES a permission" do
      it "may grant a role that turns a permission it lacks OFF" do
        workspace = current_workspace
        user = user_in(workspace)
        policy = described_class.new(user, create(:membership, workspace: workspace))
        locked = create(:role, workspace: workspace, name: "Locked", slug: "locked",
                               permissions: { "manage_workspace" => false })
        expect(policy.may_grant?(locked)).to be(true)
      end
    end

    context "target membership belongs to another workspace (cross-tenant guard)" do
      it "grants nothing — the actor's home-workspace role can't authorize a foreign record" do
        workspace = current_workspace
        user = user_in(workspace, :owner)
        foreign_record = create(:membership, workspace: create(:workspace))
        policy = described_class.new(user, foreign_record)
        expect(policy.may_grant?(Role.system_default!("member"))).to be(false)
      end
    end
  end

  # SEC-1: #reactivate? is gated the same way as #update? — an actor must not
  # be able to restore an Owner seat (a role they could not grant) by
  # reactivating a deactivated membership.
  describe "#reactivate? — target rank gate" do
    context "actor is admin, target is a deactivated owner" do
      it "denies reactivate (admin cannot restore an owner)" do
        workspace = current_workspace
        user = user_in(workspace, :admin)
        record = create(:membership, :owner, user: create(:user), workspace: workspace)
        record.update!(discarded_at: Time.current)
        expect(described_class.new(user, record).reactivate?).to be(false)
      end
    end

    context "actor is admin, target is a deactivated member" do
      it "allows reactivate" do
        workspace = current_workspace
        user = user_in(workspace, :admin)
        record = create(:membership, user: create(:user), workspace: workspace)
        record.update!(discarded_at: Time.current)
        expect(described_class.new(user, record).reactivate?).to be(true)
      end
    end
  end

  # SEC-1: #update? is also gated on the target's current rank so an actor
  # cannot manage (and thereby demote) a membership whose role outranks them.
  describe "#update? — target rank gate" do
    context "actor is admin, target is owner" do
      it "denies update (admin cannot manage an owner's membership)" do
        workspace = current_workspace
        user = user_in(workspace, :admin)
        record = create(:membership, :owner, user: create(:user), workspace: workspace)
        expect(described_class.new(user, record).update?).to be(false)
      end
    end

    context "actor is admin, target is member" do
      it "allows update" do
        workspace = current_workspace
        user = user_in(workspace, :admin)
        record = create(:membership, user: create(:user), workspace: workspace)
        expect(described_class.new(user, record).update?).to be(true)
      end
    end

    context "actor is owner, target is owner" do
      it "allows update (co-owner management is legitimate)" do
        workspace = current_workspace
        user = user_in(workspace, :owner)
        record = create(:membership, :owner, user: create(:user), workspace: workspace)
        expect(described_class.new(user, record).update?).to be(true)
      end
    end
  end
end
