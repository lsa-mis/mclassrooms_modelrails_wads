require "rails_helper"

# MiClassrooms Phase 3 Task 1 (spec D5, Brief §3.2): RoomPolicy is the
# read-side authorization for the Find a Room screen. index?/show? are
# authenticated-only (DirectoryScoped already requires sign-in; the policy
# just pins that this is not further gated by role). Manual creation is
# denied for everyone — rooms exist only via the nightly sync (Brief §5.3).
# view_inactive? gates the admin-only "show hidden/not-in-feed rooms" toggle
# (Brief §14.1 — editors do NOT get inactive views this phase).
RSpec.describe RoomPolicy do
  let(:workspace) { create(:workspace) }

  # RoleResolver.for consults TenancyConfig.shared_workspace, not
  # Current.workspace directly (see spec/lib/role_resolver_spec.rb) — stub it
  # so these specs don't depend on which onboarding preset the suite runs
  # under. Current.workspace is set separately below because Room's
  # `for_current_workspace` scope (relied on by RoomPolicy::Scope) keys off
  # that instead.
  before do
    allow(TenancyConfig).to receive(:shared_workspace).and_return(workspace)
    Current.workspace = workspace
  end

  def membership_with(slug)
    user = create(:user)
    create(:membership, user: user, workspace: workspace, role: Role.system_default!(slug))
    user
  end

  let(:admin_user) { membership_with("admin") }
  let(:viewer_user) { membership_with("viewer") }
  let(:no_membership_user) { create(:user) }

  describe "#index?" do
    it "allows any signed-in user regardless of role" do
      expect(described_class.new(admin_user, Room).index?).to be true
      expect(described_class.new(viewer_user, Room).index?).to be true
      expect(described_class.new(no_membership_user, Room).index?).to be true
    end

    it "denies a nil (signed-out) user" do
      expect(described_class.new(nil, Room).index?).to be false
    end
  end

  describe "#show?" do
    let(:room) { create(:room, workspace: workspace) }

    it "allows any signed-in user regardless of role" do
      expect(described_class.new(admin_user, room).show?).to be true
      expect(described_class.new(viewer_user, room).show?).to be true
      expect(described_class.new(no_membership_user, room).show?).to be true
    end

    it "denies a nil (signed-out) user" do
      expect(described_class.new(nil, room).show?).to be false
    end
  end

  describe "#create? / #new?" do
    it "is denied for everyone — rooms exist only via sync (Brief §5.3)" do
      expect(described_class.new(admin_user, Room).create?).to be false
      expect(described_class.new(viewer_user, Room).create?).to be false
      expect(described_class.new(no_membership_user, Room).create?).to be false
      expect(described_class.new(nil, Room).create?).to be false
    end

    it "mirrors create? for new? via the ApplicationPolicy default" do
      expect(described_class.new(admin_user, Room).new?).to be false
    end
  end

  describe "#view_inactive?" do
    it "allows an admin" do
      expect(described_class.new(admin_user, Room).view_inactive?).to be true
    end

    it "denies a viewer" do
      expect(described_class.new(viewer_user, Room).view_inactive?).to be false
    end

    it "denies a signed-in user with no membership" do
      expect(described_class.new(no_membership_user, Room).view_inactive?).to be false
    end

    it "denies a nil (signed-out) user" do
      expect(described_class.new(nil, Room).view_inactive?).to be false
    end
  end

  describe RoomPolicy::Scope do
    let(:building) { create(:building, workspace: workspace) }

    let!(:listed_classroom) { create(:room, building: building, workspace: workspace) }
    let!(:hidden_classroom) { create(:room, :hidden, building: building, workspace: workspace) }
    let!(:not_in_feed_classroom) { create(:room, building: building, workspace: workspace, in_feed: false) }
    let!(:non_classroom_listed) { create(:room, building: building, workspace: workspace, room_type: "Office") }

    describe "#resolve — the safe default for everyone, including admins" do
      it "returns only listed classrooms for a viewer" do
        result = described_class.new(viewer_user, Room).resolve

        expect(result).to contain_exactly(listed_classroom)
      end

      it "excludes hidden, not-in-feed, and non-classroom rooms for a viewer" do
        result = described_class.new(viewer_user, Room).resolve

        expect(result).not_to include(hidden_classroom, not_in_feed_classroom, non_classroom_listed)
      end

      it "is also the safe default for an admin — the toggle requires resolve_including_inactive" do
        result = described_class.new(admin_user, Room).resolve

        expect(result).to contain_exactly(listed_classroom)
      end

      it "returns only listed classrooms for a signed-in user with no membership" do
        result = described_class.new(no_membership_user, Room).resolve

        expect(result).to contain_exactly(listed_classroom)
      end
    end

    describe "#resolve_including_inactive" do
      it "expands to hidden and not-in-feed classrooms for an admin, but never non-classroom rooms" do
        result = described_class.new(admin_user, Room).resolve_including_inactive

        expect(result).to contain_exactly(listed_classroom, hidden_classroom, not_in_feed_classroom)
      end

      # Teeth: a non-admin calling the admin-only expansion directly (e.g. a
      # controller bug, or a crafted param bypassing the authorize check)
      # must still land on the safe default — never the inactive set.
      it "falls back to the safe default for a viewer" do
        result = described_class.new(viewer_user, Room).resolve_including_inactive

        expect(result).to contain_exactly(listed_classroom)
      end

      it "falls back to the safe default for a signed-in user with no membership" do
        result = described_class.new(no_membership_user, Room).resolve_including_inactive

        expect(result).to contain_exactly(listed_classroom)
      end

      it "falls back to the safe default for a nil (signed-out) user" do
        result = described_class.new(nil, Room).resolve_including_inactive

        expect(result).to contain_exactly(listed_classroom)
      end
    end

    it "never leaks rooms from another workspace" do
      other_workspace = create(:workspace)
      other_building = create(:building, workspace: other_workspace)
      create(:room, building: other_building, workspace: other_workspace)

      expect(described_class.new(admin_user, Room).resolve_including_inactive)
        .to contain_exactly(listed_classroom, hidden_classroom, not_in_feed_classroom)
    end
  end
end
