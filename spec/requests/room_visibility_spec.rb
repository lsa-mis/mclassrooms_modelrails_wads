require "rails_helper"

RSpec.describe "Room visibility through the room update", type: :request do
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

  def set_listed(room, listed)
    patch room_path(room), params: { room: { listed: listed ? "1" : "0" } }
  end

  it "no longer routes the standalone hide and unhide actions" do
    expect(Rails.application.routes.url_helpers).not_to respond_to(:hide_room_path)
    expect(Rails.application.routes.url_helpers).not_to respond_to(:unhide_room_path)
  end

  describe "as an admin" do
    let(:admin) { membership_with("admin") }

    before { sign_in(admin) }

    it "hides the room when listed is switched off, stays on the room page, and audits the change" do
      expect { set_listed(room_in_unit, false) }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(room_path(room_in_unit))
      expect(flash[:notice]).to eq(I18n.t("rooms.hide.success"))

      room_in_unit.reload
      expect(room_in_unit).to be_hidden
      expect(room_in_unit.hidden_by).to eq(admin)

      log = ActivityLog.last
      expect(log.action).to eq("room.hidden")
      expect(log.before_after["before"]).to eq("hidden_at" => nil, "hidden_by_id" => nil)
      expect(log.before_after["after"]["hidden_by_id"]).to eq(admin.id)
    end

    it "unhides a hidden room when listed is switched on, and audits the change" do
      room_in_unit.update!(hidden_at: Time.current, hidden_by: admin)

      expect { set_listed(room_in_unit, true) }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(room_path(room_in_unit))
      expect(flash[:notice]).to eq(I18n.t("rooms.unhide.success"))

      room_in_unit.reload
      expect(room_in_unit).not_to be_hidden
      expect(ActivityLog.last.action).to eq("room.unhidden")
    end

    it "writes nothing when listed matches the room's current state" do
      expect { set_listed(room_in_unit, true) }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(room_path(room_in_unit))
      expect(room_in_unit.reload).not_to be_hidden
    end

    it "applies a nickname change and a hide in the same save" do
      patch room_path(room_in_unit), params: { room: { nickname: "Auditorium 3", listed: "0" } }

      room_in_unit.reload
      expect(room_in_unit.nickname).to eq("Auditorium 3")
      expect(room_in_unit).to be_hidden
      expect(ActivityLog.order(:id).last(2).map(&:action)).to contain_exactly("room.updated", "room.hidden")
    end
  end

  describe "as the room's assigned-unit editor" do
    let(:editor) { editor_for(unit) }

    before { sign_in(editor) }

    it "hides the room, redirects to Find a Room (the editor loses sight of it), and audits the change" do
      expect { set_listed(room_in_unit, false) }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:notice]).to eq(I18n.t("rooms.hide.success"))

      room_in_unit.reload
      expect(room_in_unit).to be_hidden
      expect(room_in_unit.hidden_by).to eq(editor)
    end

    it "denies hiding a room outside the editor's unit and writes no ActivityLog" do
      expect { set_listed(room_other_unit, false) }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
      expect(room_other_unit.reload).not_to be_hidden
    end

    it "denies hiding a room with no unit (admin-only) and writes no ActivityLog" do
      expect { set_listed(room_no_unit, false) }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
      expect(room_no_unit.reload).not_to be_hidden
    end

    it "denies unhiding, even on the editor's own unit's room (one-way hide)" do
      room_in_unit.update!(hidden_at: Time.current, hidden_by: editor)

      expect { set_listed(room_in_unit, true) }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
      expect(room_in_unit.reload).to be_hidden
    end

    it "redirects the editor away from the room once it is hidden" do
      set_listed(room_in_unit, false)

      get room_path(room_in_unit)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:notice]).to eq(I18n.t("rooms.inactive_notice"))
    end
  end
end
