require "rails_helper"

# MiClassrooms Phase 5 Task 6 (Brief §14.1): the editor-facing room edit —
# RoomPolicy#update?/#edit? now admit the room's unit editor (Task 3), but
# RoomPolicy#manage_media? stays admin-only. This is the authorization
# BOUNDARY proof: RoomsController#room_params strong-params branch must strip
# every media key server-side for an editor's request, not merely hide the
# controls in the view — an editor crafting `{ room: { photo: <file> } }`
# directly must never attach anything. Mirrors
# spec/requests/room_visibility_spec.rb's tenancy setup (shared-posture stub
# + workspace-scoped fixtures + sign_in) and its `editor_for` helper (a plain
# viewer-role membership PLUS an EditorAssignment on a specific unit).
RSpec.describe "PATCH /rooms/:id — editor-scoped room edit", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-update-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # Same reuse-and-re-role pattern as rooms_spec.rb/room_visibility_spec.rb:
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
  # the EditorAssignment table, not the Membership role.
  def editor_for(unit)
    user = membership_with("viewer")
    create(:editor_assignment, user: user, unit: unit)
    user
  end

  let(:building) { create(:building, workspace: workspace) }
  let(:unit) { create(:unit, workspace: workspace) }
  let(:other_unit) { create(:unit, workspace: workspace) }
  let!(:room_in_unit) do
    create(:room, building: building, workspace: workspace, unit: unit,
           facility_code: "MLB1001", nickname: "Old Name")
  end
  let!(:room_other_unit) do
    create(:room, building: building, workspace: workspace, unit: other_unit, facility_code: "MLB1002")
  end

  describe "as the room's assigned-unit editor" do
    let(:editor) { editor_for(unit) }

    before { sign_in(editor) }

    # The crux security proof: nickname (permitted for an editor) updates,
    # photo (stripped by room_params' strong-params branch, since
    # RoomPolicy#manage_media? is admin-only) never reaches
    # Room#photo=/Curation::Apply at all — not merely unattached because the
    # editor never SAW a file input, but because the server dropped the
    # param regardless of what the client sent. Exactly one ActivityLog,
    # scoped to the curated half of the split (room.updated), whose
    # before_after covers only the field that actually changed.
    it "updates the curated field, silently drops the media param, and audits only the curated change" do
      expect {
        patch room_path(room_in_unit), params: {
          room: { nickname: "Aud 3", photo: fixture_file_upload("avatar.png", "image/png") }
        }
      }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(room_path(room_in_unit))
      expect(room_in_unit.reload.nickname).to eq("Aud 3")
      expect(room_in_unit.photo).not_to be_attached

      log = ActivityLog.last
      expect(log.action).to eq("room.updated")
      expect(log.before_after).to eq(
        "before" => { "nickname" => "Old Name" }, "after" => { "nickname" => "Aud 3" }
      )
    end

    it "denies PATCH on a room outside the editor's assigned unit, with no changes and no ActivityLog" do
      expect {
        patch room_path(room_other_unit), params: { room: { nickname: "Hijacked" } }
      }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
      expect(room_other_unit.reload.nickname).to be_nil
    end

    # View-level companion to the strong-params proof above: the media
    # sections partial (photo/panorama/seating_chart/gallery inputs) must not
    # even RENDER for an editor — RoomPolicy#manage_media? gates it in
    # rooms/edit.html.erb — replaced by the admin-only-media hint (§14.1:
    # editors flag media issues via notes, not by managing media directly).
    # The curated fields (nickname/ADA seat count) still render.
    it "renders the curated fields and the media-admin-only hint, but not the media inputs" do
      get edit_room_path(room_in_unit)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("rooms.edit.nickname_label"))
      expect(response.body).to include(I18n.t("rooms.edit.ada_seat_count_label"))
      expect(response.body).to include(I18n.t("rooms.edit.media_admin_only_hint"))
      expect(response.body).to include(I18n.t("rooms.edit.media_admin_only_hint_link"))
      expect(response.body).not_to include(I18n.t("rooms.edit.photo_hint"))
      expect(response.body).not_to include(I18n.t("rooms.edit.gallery_heading"))
    end
  end

  describe "as an admin" do
    let(:admin) { membership_with("admin") }

    before { sign_in(admin) }

    # Same request the editor spec above sends — an admin gets BOTH: the
    # curated field updates AND the photo attaches, each audited separately
    # (the curated/media Curation::Apply split, Phase 5 Task 6 deliverable
    # 3) — "appropriate ActivityLog(s)" per the task brief, plural allowed.
    it "updates the curated field AND attaches the submitted media, auditing both halves" do
      expect {
        patch room_path(room_in_unit), params: {
          room: { nickname: "Aud 3", photo: fixture_file_upload("avatar.png", "image/png") }
        }
      }.to change(ActivityLog, :count).by(2)

      expect(response).to redirect_to(room_path(room_in_unit))
      expect(room_in_unit.reload.nickname).to eq("Aud 3")
      expect(room_in_unit.photo).to be_attached

      expect(ActivityLog.where(action: "room.updated", trackable: room_in_unit).count).to eq(1)
      expect(ActivityLog.where(action: "room.media_updated", trackable: room_in_unit).count).to eq(1)
    end

    it "renders both the curated fields and the media sections, not the editor hint" do
      get edit_room_path(room_in_unit)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("rooms.edit.nickname_label"))
      expect(response.body).to include(I18n.t("rooms.edit.photo_hint"))
      expect(response.body).to include(I18n.t("rooms.edit.gallery_heading"))
      expect(response.body).not_to include(I18n.t("rooms.edit.media_admin_only_hint"))
    end
  end
end
