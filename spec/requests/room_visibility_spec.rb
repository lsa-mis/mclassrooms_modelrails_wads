require "rails_helper"

RSpec.describe "Room visibility as a hiding resource", type: :request do
  let(:workspace) { create(:workspace, slug: "room-visibility-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
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
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  it "routes hiding as a room's hiding resource, and the room update no longer takes listed" do
    expect(Rails.application.routes.recognize_path("/rooms/1/hiding", method: :post))
      .to include(controller: "rooms/hidings", action: "create", room_id: "1")
    expect(Rails.application.routes.recognize_path("/rooms/1/hiding", method: :delete))
      .to include(controller: "rooms/hidings", action: "destroy", room_id: "1")
    expect(Rails.application.routes.url_helpers).not_to respond_to(:hide_room_path)
  end

  describe "as an admin" do
    let(:admin) { membership_with("admin") }

    before { sign_in(admin) }

    it "hides the room, stays in edit mode, and audits the change" do
      expect { post room_hiding_path(room_in_unit) }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(edit_room_path(room_in_unit))
      expect(flash[:notice]).to eq(I18n.t("rooms.hide.success"))

      room_in_unit.reload
      expect(room_in_unit).to be_hidden
      expect(room_in_unit.hidden_by).to eq(admin)

      log = ActivityLog.last
      expect(log.action).to eq("room.hidden")
      expect(log.before_after["before"]).to eq("hidden_at" => nil, "hidden_by_id" => nil)
      expect(log.before_after["after"]["hidden_by_id"]).to eq(admin.id)
    end

    it "answers a Turbo request in place: the switch, the hidden marker on the media, and a toast" do
      post room_hiding_path(room_in_unit), headers: turbo

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(stream_shape).to eq([
        [ "replace", "room_visibility", "morph" ],
        [ "update", "room_media_view", nil ],
        [ "append", "toast-pills", nil ]
      ])
      switch = Nokogiri::HTML5.fragment(streams.first.at_css("template").inner_html)
      expect(switch.at_css("input#room_listed")["checked"]).to be_nil
      expect(switch.at_css("form input[name='_method']")["value"]).to eq("delete")
      expect(streams[1].inner_html).to include(I18n.t("rooms.show.hidden_overlay"))
      expect(streams.last.inner_html).to include(I18n.t("rooms.hide.success"))
    end

    it "unhides a hidden room, and audits the change" do
      room_in_unit.update!(hidden_at: Time.current, hidden_by: admin)

      expect { delete room_hiding_path(room_in_unit) }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(edit_room_path(room_in_unit))
      expect(flash[:notice]).to eq(I18n.t("rooms.unhide.success"))
      expect(room_in_unit.reload).not_to be_hidden
      expect(ActivityLog.last.action).to eq("room.unhidden")
    end

    it "ignores listed on the room update, which saves only the room's own fields" do
      patch room_path(room_in_unit), params: { room: { nickname: "Auditorium 3", listed: "0" } }

      room_in_unit.reload
      expect(room_in_unit.nickname).to eq("Auditorium 3")
      expect(room_in_unit).not_to be_hidden
    end
  end

  describe "as the room's assigned-unit editor" do
    let(:editor) { editor_for(unit) }

    before { sign_in(editor) }

    it "hides the room and sends the editor to Find a Room, since they lose sight of it" do
      expect { post room_hiding_path(room_in_unit), headers: turbo }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:notice]).to eq(I18n.t("rooms.hide.success"))

      room_in_unit.reload
      expect(room_in_unit).to be_hidden
      expect(room_in_unit.hidden_by).to eq(editor)
    end

    it "denies hiding a room outside the editor's unit and writes no ActivityLog" do
      expect { post room_hiding_path(room_other_unit) }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
      expect(room_other_unit.reload).not_to be_hidden
    end

    it "denies hiding a room with no unit (admin-only) and writes no ActivityLog" do
      expect { post room_hiding_path(room_no_unit) }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
      expect(room_no_unit.reload).not_to be_hidden
    end

    it "denies unhiding, even on the editor's own unit's room (one-way hide)" do
      room_in_unit.update!(hidden_at: Time.current, hidden_by: editor)

      expect { delete room_hiding_path(room_in_unit) }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
      expect(room_in_unit.reload).to be_hidden
    end

    it "redirects the editor away from the room once it is hidden" do
      post room_hiding_path(room_in_unit)

      get room_path(room_in_unit)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:notice]).to eq(I18n.t("rooms.inactive_notice"))
    end
  end
end
