require "rails_helper"

# MiClassrooms Phase 5 Task 3 (Brief §14.1): RoomPolicy is now
# RoleResolver-driven — a single ROOM_MATRIX table (admin / editor-in-unit /
# editor-in-another-unit / plain viewer) drives every action-method example,
# replacing the phase-3/4 viewer-only assumptions (index?/show? used to be
# "any signed-in user" — see git history for the superseded examples). The
# Scope tests below are unchanged from phase 3: RoomPolicy::Scope#resolve is
# still the safe default for every caller including admins, widened only via
# #resolve_including_inactive behind the admin-only view_inactive? gate.
RSpec.describe RoomPolicy do
  include_context "role matrix"

  # Brief §14.1 verbatim. Columns: admin, editor-in-unit, editor-other-unit, viewer.
  ROOM_MATRIX = [
    [ :show?,               :room_in_unit,        true,  true,  true,  true  ],
    [ :show?,               :hidden_room_in_unit, true,  false, false, false ],
    [ :update?,             :room_in_unit,        true,  true,  false, false ],
    [ :update?,             :room_other_unit,     true,  false, true,  false ],
    [ :update?,             :room_no_unit,        true,  false, false, false ],
    [ :update?,             :hidden_room_in_unit, true,  false, false, false ],
    [ :hide?,               :room_in_unit,        true,  true,  false, false ],
    [ :hide?,               :room_no_unit,        true,  false, false, false ],
    [ :unhide?,             :hidden_room_in_unit, true,  false, false, false ],
    [ :manage_media?,       :room_in_unit,        true,  false, false, false ],
    [ :destroy_attachment?, :room_in_unit,        true,  false, false, false ],
    [ :create?,             :room_in_unit,        false, false, false, false ],
    [ :destroy?,            :room_in_unit,        false, false, false, false ]
  ].freeze

  ROOM_USERS = %i[admin_user editor_user other_editor_user viewer_user].freeze

  ROOM_MATRIX.each do |action, record_name, *expected|
    ROOM_USERS.each_with_index do |user_name, i|
      it "#{action} on #{record_name} is #{expected[i]} for #{user_name}" do
        policy = described_class.new(send(user_name), send(record_name))
        expect(policy.public_send(action)).to be expected[i]
      end
    end
  end

  # Whole-branch review M-6: the matrix above pins hide? on a room the
  # editor's own unit still has VISIBLE (true), but no example directly
  # covers the one-way-hide guard itself — a unit editor re-attempting
  # hide? on a room already hidden (visible_record? false). Behavior is
  # already correct (RoomPolicy#hide? requires visible_record? for a
  # non-admin); this just pins it.
  describe "#hide? guards against re-hiding an already-hidden room" do
    it "denies a unit editor hiding a room in their own unit that is already hidden" do
      policy = described_class.new(editor_user, hidden_room_in_unit)
      expect(policy.hide?).to be false
    end
  end

  # edit?/floor_plan? mirror update?/show? exactly (ApplicationPolicy's own
  # new?/edit? aliasing convention) — not in the §14.1 matrix table itself,
  # but pinned here so the aliasing doesn't silently drift from its target.
  describe "#edit? / #floor_plan? aliasing" do
    it "edit? mirrors update? for every actor" do
      ROOM_USERS.each do |user_name|
        policy = described_class.new(send(user_name), room_in_unit)
        expect(policy.edit?).to eq(policy.update?)
      end
    end

    it "floor_plan? mirrors show? for every actor" do
      ROOM_USERS.each do |user_name|
        policy = described_class.new(send(user_name), room_in_unit)
        expect(policy.floor_plan?).to eq(policy.show?)
      end
    end
  end

  # Not in the §14.1 matrix (it gates RoomsController's admin-only inactive
  # toggle, not a room-record action), but required by
  # RoomsController#base_scope's `authorize Room, :view_inactive?` — kept
  # from the phase-3 spec, adapted to grant.admin? for consistency with every
  # other predicate above.
  describe "#view_inactive?" do
    it "allows an admin" do
      expect(described_class.new(admin_user, Room).view_inactive?).to be true
    end

    it "denies a viewer" do
      expect(described_class.new(viewer_user, Room).view_inactive?).to be false
    end
  end

  # MiClassrooms Phase 3 Task 1: RoomPolicy::Scope's airtightness tests,
  # carried over unchanged by Task 5 Task 3's matrix rewrite —
  # RoomsController#index relies on both #resolve and
  # #resolve_including_inactive, and neither method's behavior changed in
  # this task (only the action-method predicates above did).
  describe RoomPolicy::Scope do
    let(:no_membership_user) { create(:user) }

    # RoleResolver.for consults TenancyConfig.shared_workspace, not
    # Current.workspace directly (see spec/lib/role_resolver_spec.rb) — stub
    # it so these specs don't depend on which onboarding preset the suite
    # runs under. The outer "role matrix" context already sets
    # Current.workspace = workspace, which Room's `for_current_workspace`
    # scope (relied on by RoomPolicy::Scope) keys off directly.
    before { allow(TenancyConfig).to receive(:shared_workspace).and_return(workspace) }

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
