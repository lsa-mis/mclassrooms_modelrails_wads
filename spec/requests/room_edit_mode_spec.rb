require "rails_helper"

RSpec.describe "Room page view and edit modes", type: :request do
  let(:workspace) { create(:workspace, slug: "room-edit-mode-spec", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let(:building) { create(:building, workspace: workspace, name: "Mason Hall") }
  let(:unit) { create(:unit, workspace: workspace) }
  let!(:room) do
    create(:room, building: building, workspace: workspace, unit: unit,
           facility_code: "MAS1401", instructional_seat_count: 45, ada_seat_count: 2)
  end
  let(:admin) { membership_with("admin") }
  let(:editor) { editor_for(unit) }

  describe "viewing (GET /rooms/:id)" do
    it "shows an editor the same page a viewer sees, plus the Edit room link" do
      sign_in(editor)
      get room_path(room)

      expect(page).to have_link(I18n.t("rooms.show.edit_link"), href: edit_room_path(room))
      expect(page).to have_no_button("Hide room")
      expect(page).to have_no_css("##{ActionView::RecordIdentifier.dom_id(room, :new_note)}")
      expect(page).to have_no_link(I18n.t("rooms.show.add_photos"))
      expect(page).to have_css("[data-room-mode='view']")
    end

    it "gives a viewer no Edit room link" do
      sign_in(membership_with("viewer"))
      get room_path(room)

      expect(page).to have_no_link(I18n.t("rooms.show.edit_link"))
    end

    it "marks a hidden room for an admin with the hidden overlay instead of a banner" do
      room.update!(hidden_at: Time.current, hidden_by: admin)
      sign_in(admin)
      get room_path(room)

      expect(page).to have_css("[data-testid='hidden-overlay']", text: I18n.t("rooms.show.hidden_overlay"))
      expect(page).to have_no_text("This room is hidden from Find a Room results.")
      expect(page).to have_no_button("Unhide room")
    end
  end

  describe "editing (GET /rooms/:id/edit)" do
    it "renders the room page in edit mode with the curated fields bound to one form" do
      sign_in(editor)
      get edit_room_path(room)

      expect(response).to have_http_status(:ok)
      expect(page).to have_css("[data-room-mode='edit']")
      expect(page).to have_css("h1", text: room.display_name)
      expect(page).to have_css("form#room-edit-form[action='#{room_path(room)}']")
      expect(page).to have_field(I18n.t("rooms.edit.nickname_label"))
      expect(page).to have_css("input[name='room[nickname]'][form='room-edit-form']")
      expect(page).to have_css("input[name='room[ada_seat_count]'][form='room-edit-form'][value='2']")
      expect(page).to have_css("input[role='switch'][name='room[listed]'][form='room-edit-form'][checked]")
      expect(page).to have_css("input[type='hidden'][name='room[listed]'][value='0'][form='room-edit-form']", visible: :all)
      expect(page).to have_button(I18n.t("rooms.edit.submit"))
      expect(page).to have_css("button[form='room-edit-form']", text: I18n.t("rooms.edit.submit"))
      expect(page).to have_link(I18n.t("rooms.edit.cancel"), href: room_path(room))
      expect(page).to have_no_link(I18n.t("rooms.show.edit_link"))
      expect(page).to have_no_button(I18n.t("rooms.save.save"))
    end

    it "labels the synced seat count as coming from Facilities" do
      sign_in(editor)
      get edit_room_path(room)

      expect(page).to have_text(I18n.t("rooms.edit.synced_seats", count: 45))
      expect(page).to have_text(I18n.t("rooms.edit.synced_sections"))
    end

    it "gives the editor the note composer and the admin-managed media hint, but no media controls" do
      attach_panorama!(room)
      sign_in(editor)
      get edit_room_path(room)

      expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(room, :new_note)}")
      expect(page).to have_text(I18n.t("rooms.edit.media_admin_only_hint"))
      expect(page).to have_no_button(I18n.t("rooms.edit.edit_panorama"))
      expect(page).to have_no_css("input[type='file']")
    end

    it "gives an admin the panorama and seating chart editors as dialogs, each with its own form" do
      attach_panorama!(room)
      sign_in(admin)
      get edit_room_path(room)

      expect(page).to have_button(I18n.t("rooms.edit.edit_panorama"))
      expect(page).to have_button(I18n.t("rooms.edit.add_seating_chart"))
      expect(page).to have_css("dialog form[action='#{room_path(room)}'] input[type='file'][name='room[panorama]']", visible: :all)
      expect(page).to have_css("dialog form[action='#{room_path(room)}'] input[type='file'][name='room[seating_chart]']", visible: :all)
    end

    it "tells an admin that a room outside the Facilities feed isn't listed, whatever the switch says" do
      room.update!(in_feed: false)
      sign_in(admin)
      get edit_room_path(room)

      expect(page).to have_css("#room_listed_feed_hint", text: I18n.t("rooms.edit.listed_out_of_feed"))
      expect(page).to have_css("input[role='switch'][aria-describedby~='room_listed_feed_hint']")
    end

    it "gives an admin the add-media affordances on a room with no media" do
      sign_in(admin)
      get edit_room_path(room)

      expect(page).to have_button(I18n.t("rooms.edit.add_panorama"))
      expect(page).to have_button(I18n.t("rooms.show.add_photos"))
    end
  end

  describe "saving (PATCH /rooms/:id)" do
    def stray_upload
      Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/stray.txt"), "text/plain")
    end

    it "re-renders the room page in edit mode and reopens the seating chart dialog when its upload fails" do
      sign_in(admin)
      patch room_path(room), params: { room: { seating_chart: stray_upload } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(page).to have_css("[data-room-mode='edit']")
      expect(page).to have_css("[data-modal-open-value='true'] dialog#seating-chart-editor", visible: :all)
      expect(page).to have_no_css("[data-modal-open-value='true'] dialog#panorama-editor", visible: :all)
    end

    it "reports a stale gallery row inside the reopened photos sheet" do
      sign_in(admin)
      patch room_path(room), params: { room: { gallery_attributes: { "0" => { id: "999999", position: "1" } } } }

      expect(response).to have_http_status(:unprocessable_entity)
      sheet = page.find("[data-modal-open-value='true'] dialog#gallery-editor", visible: :all)
      expect(sheet.text(:all)).to include(I18n.t("rooms.edit.stale_gallery"))
    end

    it "reopens the panorama dialog when a panorama upload fails" do
      sign_in(admin)
      patch room_path(room), params: { room: { panorama: stray_upload } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(page).to have_css("[data-modal-open-value='true'] dialog#panorama-editor", visible: :all)
    end
  end
end
