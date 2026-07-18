require "rails_helper"

# MiClassrooms Phase 8 Task 3 (D18, Brief §5.9): the four retired Classroom
# Database URLs the old app exposed must keep resolving after cutover so
# bookmarks, registrar links, and deep links don't 404. All are unauthenticated
# (old deep links arrive signed out) and redirect-only.
RSpec.describe "Legacy URL redirects (D18)", type: :request do
  let(:workspace) { create(:workspace, slug: "legacy-redirects-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let(:building) { create(:building, workspace: workspace) }
  let!(:room) { create(:room, building: building, workspace: workspace, facility_code: "MLB1200") }

  describe "GET /classrooms/:facility_code" do
    it "redirects a known facility code (case-insensitive) to the room, with an outdated-link notice" do
      get "/classrooms/mlb1200"

      expect(response).to redirect_to(room_path(room))
      expect(response).to have_http_status(:found) # 302: a code unknown today may resolve after a later sync
      expect(flash[:notice]).to eq(I18n.t("legacy_redirects.outdated_link"))
    end

    it "redirects an unknown facility code to Find a Room with an alert" do
      get "/classrooms/zzz9999"

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:alert]).to eq(I18n.t("legacy_redirects.unknown_code"))
    end
  end

  describe "GET /classrooms (retired LSA index)" do
    it "permanently redirects to Find a Room filtered to the LSA unit when present" do
      lsa = create(:unit, workspace: workspace, department_group: "COLLEGE_OF_LSA")

      get "/classrooms"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(find_a_room_path(unit_id: lsa.id))
    end

    it "permanently redirects to plain Find a Room when the LSA unit isn't synced yet" do
      get "/classrooms"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(find_a_room_path)
    end
  end

  describe "GET /legacy_crdb" do
    it "permanently redirects to the retired LSA classroom database host" do
      get "/legacy_crdb"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to("https://rooms.lsa.umich.edu")
    end
  end

  describe "GET /toggle_visibile/:id (old visibility toggle)" do
    it "redirects a known rmrecnbr to the room's edit page (where hide/unhide now lives)" do
      get "/toggle_visibile/#{room.rmrecnbr}"

      expect(response).to redirect_to(edit_room_path(room))
      expect(flash[:notice]).to eq(I18n.t("legacy_redirects.visibility_moved"))
    end

    it "redirects an unknown id to Find a Room" do
      get "/toggle_visibile/999999999"

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:alert]).to eq(I18n.t("legacy_redirects.unknown_code"))
    end
  end
end
