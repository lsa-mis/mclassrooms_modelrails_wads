require "rails_helper"

RSpec.describe "PATCH /rooms/:id — editor-scoped room edit", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-update-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
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

    it "updates the curated field, silently drops the media param, and audits only the curated change" do
      expect {
        patch room_path(room_in_unit), params: {
          room: { nickname: "Aud 3", seating_chart: fixture_file_upload("avatar.png", "image/png") }
        }
      }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(room_path(room_in_unit))
      expect(room_in_unit.reload.nickname).to eq("Aud 3")
      expect(room_in_unit.seating_chart).not_to be_attached

      log = ActivityLog.last
      expect(log.action).to eq("room.updated")
      expect(log.before_after).to eq(
        "before" => { "nickname" => "Old Name" }, "after" => { "nickname" => "Aud 3" }
      )
    end

    it "is refused the seating chart resource, since media is admin-only" do
      expect {
        patch room_seating_chart_path(room_in_unit), params: {
          room: { seating_chart: fixture_file_upload("avatar.png", "image/png") }
        }
      }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(find_a_room_path)
      expect(room_in_unit.reload.seating_chart).not_to be_attached
    end

    it "denies PATCH on a room outside the editor's assigned unit, with no changes and no ActivityLog" do
      expect {
        patch room_path(room_other_unit), params: { room: { nickname: "Hijacked" } }
      }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
      expect(room_other_unit.reload.nickname).to be_nil
    end

    it "renders the curated fields and the media-admin-only hint, but not the media inputs" do
      get edit_room_path(room_in_unit)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("rooms.edit.nickname_label"))
      expect(response.body).to include(I18n.t("rooms.edit.ada_seat_count_label"))
      expect(response.body).to include(I18n.t("rooms.edit.media_admin_only_hint"))
      expect(response.body).not_to include(I18n.t("rooms.edit.seating_chart_hint"))
      expect(response.body).not_to include(I18n.t("rooms.edit.gallery_heading"))
    end
  end

  describe "as an admin" do
    let(:admin) { membership_with("admin") }

    before { sign_in(admin) }

    it "saves the room's own fields through the room, and a seating chart through its own resource" do
      patch room_path(room_in_unit), params: {
        room: { nickname: "Aud 3", seating_chart: fixture_file_upload("avatar.png", "image/png") }
      }
      expect(room_in_unit.reload.nickname).to eq("Aud 3")
      expect(room_in_unit.seating_chart).not_to be_attached

      expect {
        patch room_seating_chart_path(room_in_unit), params: {
          room: { seating_chart: fixture_file_upload("avatar.png", "image/png") }
        }
      }.to change(ActivityLog.where(action: "room.media_updated", trackable: room_in_unit), :count).by(1)

      expect(response).to redirect_to(edit_room_path(room_in_unit))
      expect(room_in_unit.reload.seating_chart).to be_attached
    end

    it "renders both the curated fields and the media sections, not the editor hint" do
      get edit_room_path(room_in_unit)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("rooms.edit.nickname_label"))
      expect(response.body).to include(I18n.t("rooms.edit.seating_chart_hint"))
      expect(response.body).to include(I18n.t("rooms.edit.gallery_heading"))
      expect(response.body).not_to include(I18n.t("rooms.edit.media_admin_only_hint"))
    end
  end
end
