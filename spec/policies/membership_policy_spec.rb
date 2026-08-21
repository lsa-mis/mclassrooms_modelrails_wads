require "rails_helper"

RSpec.describe MembershipPolicy do
  let(:workspace) { create(:workspace) }

  before { Current.workspace = workspace }

  describe "for owner" do
    let(:user) { create(:user) }
    let(:other_membership) { create(:membership, workspace: workspace) }
    before { create(:membership, :owner, user: user, workspace: workspace) }

    it "allows index" do
      expect(described_class.new(user, other_membership).index?).to be true
    end

    it "allows update" do
      expect(described_class.new(user, other_membership).update?).to be true
    end

    it "allows destroy" do
      expect(described_class.new(user, other_membership).destroy?).to be true
    end

    it "denies destroying self" do
      own_membership = workspace.memberships.kept.find_by(user: user)
      expect(described_class.new(user, own_membership).destroy?).to be false
    end

    it "allows reactivate" do
      expect(described_class.new(user, other_membership).reactivate?).to be true
    end

    it "allows transfer_ownership" do
      expect(described_class.new(user, other_membership).transfer_ownership?).to be true
    end
  end

  describe "for member" do
    let(:user) { create(:user) }
    let(:other_membership) { create(:membership, workspace: workspace) }
    before { create(:membership, user: user, workspace: workspace) }

    it "allows index" do
      expect(described_class.new(user, other_membership).index?).to be true
    end

    it "denies update" do
      expect(described_class.new(user, other_membership).update?).to be false
    end

    it "denies destroy" do
      expect(described_class.new(user, other_membership).destroy?).to be false
    end

    it "denies transfer_ownership" do
      expect(described_class.new(user, other_membership).transfer_ownership?).to be false
    end
  end

  describe "#destroy? — admin deactivates someone else" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let!(:admin_membership) { create(:membership, :admin, user: user, workspace: workspace) }
    let(:record) { create(:membership, user: other_user, workspace: workspace) }
    subject(:policy) { described_class.new(user, record) }

    it "permits admin to deactivate another member" do
      expect(policy.destroy?).to be(true)
    end

    it "denies when the workspace is discarded" do
      workspace.discard!
      record.reload
      expect(policy.destroy?).to be(false)
    end
  end

  describe "#destroy? — user leaves own membership" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let(:record) { create(:membership, user: user, workspace: workspace) }
    let!(:owner_membership_other) { create(:membership, :owner, user: other_user, workspace: workspace) }
    subject(:policy) { described_class.new(user, record) }

    it "permits leaving when not last owner and not personal workspace" do
      expect(policy.destroy?).to be(true)
    end

    it "denies leaving the user's personal workspace" do
      user.update!(personal_workspace_id: workspace.id)
      expect(policy.destroy?).to be(false)
    end

    it "permits an owner leaving while another owner remains" do
      record.update!(role: Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" })
      expect(policy.destroy?).to be(true)
    end

    it "denies leaving when the user is the last owner" do
      owner_membership_other.discard!
      record.update!(role: Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" })
      expect(policy.destroy?).to be(false)
    end

    it "denies when the workspace is discarded" do
      workspace.discard!
      record.reload
      expect(policy.destroy?).to be(false)
    end
  end

  describe "#destroy? — non-member" do
    let(:user) { create(:user) }
    let(:actor) { create(:user) }
    let(:record) { create(:membership, user: user, workspace: workspace) }
    subject(:policy) { described_class.new(actor, record) }

    it "denies non-members" do
      expect(policy.destroy?).to be(false)
    end
  end

  # SEC-1: privilege-elevation guard. An actor may grant a role only if they
  # already hold every permission it confers.
  describe "#may_grant?" do
    let(:owner)  { Role.system_default!("owner") }
    let(:admin)  { Role.system_default!("admin") }
    let(:member) { Role.system_default!("member") }
    let(:viewer) { Role.system_default!("viewer") }
    let(:record) { create(:membership, workspace: workspace) }
    subject(:policy) { described_class.new(user, record) }

    context "actor is owner" do
      let(:user) { create(:user) }
      before { create(:membership, :owner, user: user, workspace: workspace) }

      it "may grant owner" do
        expect(policy.may_grant?(owner)).to be(true)
      end

      it "may grant admin" do
        expect(policy.may_grant?(admin)).to be(true)
      end
    end

    context "actor is admin" do
      let(:user) { create(:user) }
      before { create(:membership, :admin, user: user, workspace: workspace) }

      it "may NOT grant owner (no manage_workspace)" do
        expect(policy.may_grant?(owner)).to be(false)
      end

      it "may NOT grant a custom role that confers a permission it lacks" do
        superadmin = create(:role, workspace: workspace, name: "Superadmin", slug: "superadmin",
                                   permissions: { "manage_workspace" => true })
        expect(policy.may_grant?(superadmin)).to be(false)
      end

      it "may grant admin (lateral)" do
        expect(policy.may_grant?(admin)).to be(true)
      end

      it "may grant member" do
        expect(policy.may_grant?(member)).to be(true)
      end

      it "may grant viewer" do
        expect(policy.may_grant?(viewer)).to be(true)
      end
    end

    context "actor is member" do
      let(:user) { create(:user) }
      before { create(:membership, user: user, workspace: workspace) }

      it "may NOT grant admin" do
        expect(policy.may_grant?(admin)).to be(false)
      end

      it "may grant viewer (member holds no permissions viewer requires)" do
        expect(policy.may_grant?(viewer)).to be(true)
      end
    end

    context "actor has no membership in the current workspace" do
      let(:user) { create(:user) }

      it "may grant nothing, not even viewer" do
        expect(policy.may_grant?(viewer)).to be(false)
        expect(policy.may_grant?(admin)).to be(false)
      end
    end

    context "actor is member; custom role explicitly DISABLES a permission" do
      let(:user) { create(:user) }
      before { create(:membership, user: user, workspace: workspace) }

      it "may grant a role that turns a permission it lacks OFF" do
        locked = create(:role, workspace: workspace, name: "Locked", slug: "locked",
                               permissions: { "manage_workspace" => false })
        expect(policy.may_grant?(locked)).to be(true)
      end
    end

    context "target membership belongs to another workspace (cross-tenant guard)" do
      let(:user) { create(:user) }
      let(:other_workspace) { create(:workspace) }
      let(:record) { create(:membership, workspace: other_workspace) }
      before { create(:membership, :owner, user: user, workspace: workspace) }

      it "grants nothing — the actor's home-workspace role can't authorize a foreign record" do
        expect(policy.may_grant?(member)).to be(false)
      end
    end
  end

  # SEC-1: #reactivate? is gated the same way as #update? — an actor must not
  # be able to restore an Owner seat (a role they could not grant) by
  # reactivating a deactivated membership.
  describe "#reactivate? — target rank gate" do
    let(:user) { create(:user) }
    subject(:policy) { described_class.new(user, record) }

    context "actor is admin, target is a deactivated owner" do
      let(:owner_user) { create(:user) }
      let(:record) { create(:membership, :owner, user: owner_user, workspace: workspace) }
      before do
        create(:membership, :admin, user: user, workspace: workspace)
        record.discard!
      end

      it "denies reactivate (admin cannot restore an owner)" do
        expect(policy.reactivate?).to be(false)
      end
    end

    context "actor is admin, target is a deactivated member" do
      let(:member_user) { create(:user) }
      let(:record) { create(:membership, user: member_user, workspace: workspace) }
      before do
        create(:membership, :admin, user: user, workspace: workspace)
        record.discard!
      end

      it "allows reactivate" do
        expect(policy.reactivate?).to be(true)
      end
    end
  end

  # SEC-1: #update? is also gated on the target's current rank so an actor
  # cannot manage (and thereby demote) a membership whose role outranks them.
  describe "#update? — target rank gate" do
    let(:user) { create(:user) }
    subject(:policy) { described_class.new(user, record) }

    context "actor is admin, target is owner" do
      let(:owner_user) { create(:user) }
      let(:record) { create(:membership, :owner, user: owner_user, workspace: workspace) }
      before { create(:membership, :admin, user: user, workspace: workspace) }

      it "denies update (admin cannot manage an owner's membership)" do
        expect(policy.update?).to be(false)
      end
    end

    context "actor is admin, target is member" do
      let(:member_user) { create(:user) }
      let(:record) { create(:membership, user: member_user, workspace: workspace) }
      before { create(:membership, :admin, user: user, workspace: workspace) }

      it "allows update" do
        expect(policy.update?).to be(true)
      end
    end

    context "actor is owner, target is owner" do
      let(:owner_user) { create(:user) }
      let(:record) { create(:membership, :owner, user: owner_user, workspace: workspace) }
      before { create(:membership, :owner, user: user, workspace: workspace) }

      it "allows update (co-owner management is legitimate)" do
        expect(policy.update?).to be(true)
      end
    end
  end
end
