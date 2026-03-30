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
  end
end
