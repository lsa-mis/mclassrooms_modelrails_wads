require "rails_helper"

RSpec.describe "Room media as nested resources", type: :request do
  let(:workspace) { create(:workspace, slug: "room-media-resources-spec", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let(:building) { create(:building, workspace: workspace) }
  let(:unit) { create(:unit, workspace: workspace) }
  let!(:room) { create(:room, building: building, workspace: workspace, unit: unit, facility_code: "MAS1401") }
  let(:admin) { membership_with("admin") }

  describe "routing" do
    def route(method, path) = Rails.application.routes.recognize_path(path, method: method)

    it "draws only resourceful routes for a room's media and floor plan" do
      expect(route(:delete, "/rooms/123/panorama")).to include(controller: "rooms/panoramas", action: "destroy", room_id: "123")
      expect(route(:delete, "/rooms/123/seating_chart")).to include(controller: "rooms/seating_charts", action: "destroy")
      expect(route(:delete, "/rooms/123/photos/9")).to include(controller: "rooms/photos", action: "destroy", id: "9")
      expect(route(:get, "/rooms/123/floor_plan")).to include(controller: "rooms/floor_plans", action: "show")
      expect(Rails.application.routes.url_helpers).not_to respond_to(:floor_plan_room_path)
    end
  end

  describe "DELETE /rooms/:room_id/panorama" do
    before { attach_panorama!(room) }

    it "removes the panorama for an admin, audits it, and reopens the panorama editor" do
      sign_in(admin)

      expect { delete room_panorama_path(room) }.to change(ActivityLog, :count).by(1)

      expect(room.reload.panorama).not_to be_attached
      expect(ActivityLog.last.action).to eq("room.media_updated")
      expect(response).to redirect_to(edit_room_path(room, open: "panorama"))
      expect(flash[:notice]).to eq(I18n.t("rooms.edit.panorama_removed"))
    end

    it "is refused for the room's unit editor and leaves the panorama" do
      sign_in(editor_for(unit))

      delete room_panorama_path(room)

      expect(response).to redirect_to(find_a_room_path)
      expect(room.reload.panorama).to be_attached
    end
  end

  describe "DELETE /rooms/:room_id/seating_chart" do
    it "removes the seating chart for an admin and reopens its editor" do
      room.seating_chart.attach(io: file_fixture("seating_chart.pdf").open, filename: "chart.pdf",
                                content_type: "application/pdf")
      sign_in(admin)

      delete room_seating_chart_path(room)

      expect(room.reload.seating_chart).not_to be_attached
      expect(response).to redirect_to(edit_room_path(room, open: "seating_chart"))
      expect(flash[:notice]).to eq(I18n.t("rooms.edit.seating_chart_removed"))
    end
  end

  describe "DELETE /rooms/:room_id/photos/:id" do
    let!(:photo) { create(:media_asset, owner: room, workspace: workspace, position: 1) }

    it "removes the photo for an admin, audits it, and reopens the photos editor" do
      sign_in(admin)

      expect { delete room_photo_path(room, photo) }.to change(ActivityLog, :count).by(1)

      expect(MediaAsset.exists?(photo.id)).to be(false)
      expect(response).to redirect_to(edit_room_path(room, open: "gallery"))
      expect(flash[:notice]).to eq(I18n.t("rooms.edit.photo_removed", position: 1))
    end

    it "never reaches another room's photo" do
      other_room = create(:room, building: building, workspace: workspace)
      foreign = create(:media_asset, owner: other_room, workspace: workspace, position: 1)
      sign_in(admin)

      delete room_photo_path(room, foreign)

      expect(MediaAsset.exists?(foreign.id)).to be(true)
    end
  end

  describe "GET /rooms/:room_id/edit?open=…" do
    before { sign_in(admin) }

    it "reopens whichever media editor it names" do
      attach_panorama!(room)

      get edit_room_path(room, open: "panorama")
      expect(page).to have_css("[data-modal-open-value='true'] dialog#panorama-editor", visible: :all)

      get edit_room_path(room, open: "seating_chart")
      expect(page).to have_css("[data-modal-open-value='true'] dialog#seating-chart-editor", visible: :all)
    end

    it "ignores a name it doesn't know" do
      get edit_room_path(room, open: "everything")

      expect(page).to have_no_css("[data-modal-open-value='true'] dialog", visible: :all)
    end
  end

  it "no longer routes removals through the room update" do
    attach_panorama!(room)
    sign_in(admin)

    patch room_path(room), params: { room: { remove_panorama: "1" } }

    expect(response).to have_http_status(:bad_request)
    expect(room.reload.panorama).to be_attached
  end
end
