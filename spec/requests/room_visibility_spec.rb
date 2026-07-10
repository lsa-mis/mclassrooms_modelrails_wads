require "rails_helper"

# MiClassrooms Phase 5 Task 5 (Brief §14.1): the visibility flows — one-way
# editor hide, admin unhide, both audited via Curation::Apply. Mirrors
# spec/requests/rooms_spec.rb's tenancy setup (shared-posture stub +
# workspace-scoped fixtures + sign_in) and spec/policies/room_policy_spec.rb's
# room fixture cast (room_in_unit / room_other_unit / room_no_unit), but as an
# end-to-end HTTP proof rather than a policy-only unit test — RoomPolicy#hide?/
# #unhide? are already pinned there; this spec proves RoomsController wires
# them correctly (redirect targets, Curation::Apply's audit trail, and the
# phase-4 post-hide-blindness redirect covering an editor).
RSpec.describe "Room visibility (hide/unhide)", type: :request do
  let(:workspace) { create(:workspace, slug: "room-visibility-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # Same reuse-and-re-role pattern as rooms_spec.rb (see that file's comment):
  # `create(:user)` auto-joins `workspace` via `User#onboard_workspace` under
  # the :shared posture stubbed above.
  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  # An editor: a plain viewer-role membership PLUS an EditorAssignment on a
  # specific unit — RoleResolver#editor?/#can_edit_room? derive entirely from
  # the EditorAssignment table, not the Membership role (app/lib/role_resolver.rb).
  def editor_for(unit)
    user = membership_with("viewer")
    create(:editor_assignment, user: user, unit: unit)
    user
  end

  let(:building) { create(:building, workspace: workspace) }
  let(:unit) { create(:unit, workspace: workspace) }
  let(:other_unit) { create(:unit, workspace: workspace) }
  let!(:room_in_unit) do
    create(:room, building: building, workspace: workspace, unit: unit, facility_code: "MLB1001")
  end
  let!(:room_other_unit) do
    create(:room, building: building, workspace: workspace, unit: other_unit, facility_code: "MLB1002")
  end
  let!(:room_no_unit) do
    create(:room, building: building, workspace: workspace, unit: nil, facility_code: "MLB1003")
  end

  describe "POST /rooms/:id/hide as an admin" do
    let(:admin) { membership_with("admin") }

    before { sign_in(admin) }

    it "hides the room, stays on the room page (admin keeps sight of it), and audits the change" do
      expect {
        post hide_room_path(room_in_unit)
      }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(room_path(room_in_unit))
      expect(flash[:notice]).to eq(I18n.t("rooms.hide.success"))

      room_in_unit.reload
      expect(room_in_unit).to be_hidden
      expect(room_in_unit.hidden_by).to eq(admin)

      log = ActivityLog.last
      expect(log.action).to eq("room.hidden")
      expect(log.before_after["before"]).to eq("hidden_at" => nil, "hidden_by_id" => nil)
      expect(log.before_after["after"]["hidden_by_id"]).to eq(admin.id)
      expect(log.before_after["after"]["hidden_at"]).to be_present
    end
  end

  describe "POST /rooms/:id/unhide as an admin" do
    let(:admin) { membership_with("admin") }

    before do
      sign_in(admin)
      room_in_unit.update!(hidden_at: Time.current, hidden_by: admin)
    end

    it "unhides the room, redirects to the room, and audits the change" do
      expect {
        post unhide_room_path(room_in_unit)
      }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(room_path(room_in_unit))
      expect(flash[:notice]).to eq(I18n.t("rooms.unhide.success"))

      room_in_unit.reload
      expect(room_in_unit).not_to be_hidden
      expect(room_in_unit.hidden_by).to be_nil

      log = ActivityLog.last
      expect(log.action).to eq("room.unhidden")
      expect(log.before_after["before"]["hidden_by_id"]).to eq(admin.id)
      expect(log.before_after["after"]).to eq("hidden_at" => nil, "hidden_by_id" => nil)
    end
  end

  describe "POST /rooms/:id/hide as the room's assigned-unit editor" do
    let(:editor) { editor_for(unit) }

    before { sign_in(editor) }

    it "hides room_in_unit, redirects to Find a Room (the editor loses sight of it), and audits the change" do
      expect {
        post hide_room_path(room_in_unit)
      }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:notice]).to eq(I18n.t("rooms.hide.success"))

      room_in_unit.reload
      expect(room_in_unit).to be_hidden
      expect(room_in_unit.hidden_by).to eq(editor)

      log = ActivityLog.last
      expect(log.action).to eq("room.hidden")
      expect(log.before_after["after"]["hidden_by_id"]).to eq(editor.id)
    end

    it "denies hiding room_other_unit (not this editor's unit) and writes no ActivityLog" do
      expect {
        post hide_room_path(room_other_unit)
      }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(workspace_path(workspace))
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
      expect(room_other_unit.reload).not_to be_hidden
    end

    it "denies hiding room_no_unit (blank unit => admin-only) and writes no ActivityLog" do
      expect {
        post hide_room_path(room_no_unit)
      }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(workspace_path(workspace))
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
      expect(room_no_unit.reload).not_to be_hidden
    end

    it "denies unhide even on the editor's own assigned-unit room (one-way hide, Brief §14.1)" do
      room_in_unit.update!(hidden_at: Time.current, hidden_by: editor)

      expect {
        post unhide_room_path(room_in_unit)
      }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(workspace_path(workspace))
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
      expect(room_in_unit.reload).to be_hidden
    end
  end

  # Post-hide blindness (Brief §14.1, phase-4 carryover): once an editor hides
  # a room, RoomsController's phase-4 `redirect_inactive_for_non_admins`
  # before_action (unchanged by this task) already covers them — an editor is
  # a non-admin, so their very next GET /rooms/:id redirects to Find a Room
  # with the same inactive notice a plain viewer would get. This is the
  # regression guard that the before_action (not a rewritten show rescue)
  # keeps working after #hide/#unhide join the routes.
  describe "post-hide blindness" do
    let(:editor) { editor_for(unit) }

    before { sign_in(editor) }

    it "redirects the editor away from the room they just hid, with the inactive notice" do
      post hide_room_path(room_in_unit)

      get room_path(room_in_unit)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:notice]).to eq(I18n.t("rooms.inactive_notice"))
    end
  end
end
