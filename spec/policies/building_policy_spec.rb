require "rails_helper"

# MiClassrooms Phase 5 Task 4 (Brief §14.1): BuildingPolicy's first dedicated
# matrix spec — Phase 4 Task 8 only ever exercised the admin-only-everywhere
# posture inline (spec/requests/buildings_spec.rb's "BuildingPolicy for a
# non-admin" example). Re-parented onto DirectoryPolicy this task, #show? now
# admits any current member on a VISIBLE building (realty/Airbnb model: the
# building page is viewer-visible, admin controls are gated within it) while
# every mutating/admin-console action (update?/hide?/unhide?/manage_media?/
# destroy_attachment?) stays admin-only. #index? stays admin-only — viewers
# reach a building only via room→building nav, never a standalone building
# index (see BuildingPolicy's header comment).
RSpec.describe BuildingPolicy do
  include_context "role matrix"

  let(:hidden_building) { create(:building, :hidden) }

  # Brief §14.1 verbatim (Task 4 table). Columns: admin, editor-in-unit,
  # editor-other-unit, viewer. Buildings have no unit/editor-assignment
  # relationship at all, so editor-in-unit and editor-other-unit behave
  # identically here — neither carries any special claim over a building.
  BUILDING_MATRIX = [
    [ :show?,               :building,        true,  true,  true,  true  ],
    [ :show?,               :hidden_building, true,  false, false, false ],
    [ :update?,             :building,        true,  false, false, false ],
    [ :hide?,               :building,        true,  false, false, false ],
    [ :unhide?,             :building,        true,  false, false, false ],
    [ :manage_media?,       :building,        true,  false, false, false ],
    [ :destroy_attachment?, :building,        true,  false, false, false ],
    [ :create?,             :building,        false, false, false, false ],
    [ :destroy?,            :building,        false, false, false, false ]
  ].freeze

  BUILDING_USERS = %i[admin_user editor_user other_editor_user viewer_user].freeze

  BUILDING_MATRIX.each do |action, record_name, *expected|
    BUILDING_USERS.each_with_index do |user_name, i|
      it "#{action} on #{record_name} is #{expected[i]} for #{user_name}" do
        policy = described_class.new(send(user_name), send(record_name))
        expect(policy.public_send(action)).to be expected[i]
      end
    end
  end

  # edit? mirrors update? exactly (ApplicationPolicy's own new?/edit?
  # aliasing convention) — not in the §14.1 matrix table itself, but pinned
  # here so the aliasing doesn't silently drift from its target.
  describe "#edit? aliasing" do
    it "mirrors update? for every actor" do
      BUILDING_USERS.each do |user_name|
        policy = described_class.new(send(user_name), building)
        expect(policy.edit?).to eq(policy.update?)
      end
    end
  end

  # Not itself a per-record row in the §14.1 matrix — BuildingsController
  # #index authorizes against the Building CLASS (`authorize Building`), not
  # a record instance, mirroring RoomPolicy's #view_inactive? standalone spec.
  describe "#index?" do
    # 2026-07-17 (Dave): the building index is now viewer-visible (supersedes
    # Task 4's admin-only listing), mirroring RoomPolicy#index? = grant.viewer?.
    it "allows an admin" do
      expect(described_class.new(admin_user, Building).index?).to be true
    end

    it "allows an editor (viewer-or-above browses the directory)" do
      expect(described_class.new(editor_user, Building).index?).to be true
    end

    it "allows a viewer" do
      expect(described_class.new(viewer_user, Building).index?).to be true
    end
  end

  # Gates the admin-only "show hidden buildings" toggle on the index.
  describe "#view_inactive?" do
    it "allows an admin" do
      expect(described_class.new(admin_user, Building).view_inactive?).to be true
    end

    it "denies an editor" do
      expect(described_class.new(editor_user, Building).view_inactive?).to be false
    end

    it "denies a viewer" do
      expect(described_class.new(viewer_user, Building).view_inactive?).to be false
    end
  end
end
