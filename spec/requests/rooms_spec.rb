require "rails_helper"

# MiClassrooms Phase 3 Task 4 (Brief §5.2, §3.2): Find a Room's controller —
# wires RoomSearch (Task 2), CharacteristicFilterGroups (Task 3), and
# RoomPolicy (Task 1) into GET /find-a-room. DirectoryScoped resolves
# Current.workspace off TenancyConfig.shared_workspace_slug (same stubbing
# pattern as spec/requests/test_login_spec.rb and directory_scoped_spec.rb),
# so every example below runs under a single shared workspace.
RSpec.describe "GET /find-a-room", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # `create(:user)` itself triggers User#onboard_workspace (after_create),
  # which — under the :shared posture stubbed above — auto-joins `workspace`
  # with TenancyConfig.shared_join_role before this method ever runs. Creating
  # a second Membership for the same (user, workspace) pair would violate the
  # user_id/workspace_id uniqueness index, so this reuses and re-roles the
  # auto-created membership instead of inserting a new one.
  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  describe "unauthenticated" do
    it "redirects to sign-in instead of rendering rooms" do
      get find_a_room_path

      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "as a viewer" do
    let(:viewer) { membership_with("viewer") }
    let(:building) { create(:building, workspace: workspace) }
    let!(:listed_classroom) { create(:room, building: building, workspace: workspace, facility_code: "MLB1001") }
    let!(:hidden_classroom) { create(:room, :hidden, building: building, workspace: workspace, facility_code: "MLB1002") }
    let!(:non_classroom) { create(:room, building: building, workspace: workspace, room_type: "Office", facility_code: "MLB1003") }

    before { sign_in(viewer) }

    it "returns 200 including the listed classroom, excluding hidden and non-classroom rooms" do
      get find_a_room_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(listed_classroom.display_name)
      expect(response.body).not_to include(hidden_classroom.display_name)
      expect(response.body).not_to include(non_classroom.display_name)
    end

    it "responds with the JSON shape: room keys + pagination block" do
      get find_a_room_path, as: :json

      json = response.parsed_body
      entry = json["rooms"].find { |r| r["id"] == listed_classroom.id }

      expect(entry.keys).to match_array(
        %w[id rmrecnbr facility_code display_name building capacity ada_capacity characteristics floor]
      )
      expect(entry["rmrecnbr"]).to eq(listed_classroom.rmrecnbr)
      expect(entry["facility_code"]).to eq(listed_classroom.facility_code)
      expect(entry["display_name"]).to eq(listed_classroom.display_name)
      expect(entry["building"]).to eq(building.display_name)
      expect(entry["capacity"]).to eq(listed_classroom.instructional_seat_count)
      expect(entry["ada_capacity"]).to eq(listed_classroom.ada_seat_count)
      expect(entry["characteristics"]).to eq([])
      expect(entry["floor"]).to be_nil

      expect(json["pagination"].keys).to match_array(%w[page pages count per])
    end
  end

  describe "pagination clamp" do
    let(:viewer) { membership_with("viewer") }
    let(:building) { create(:building, workspace: workspace) }

    before do
      create_list(:room, 35, building: building, workspace: workspace)
      sign_in(viewer)
    end

    it "clamps a client per above the max down to 100" do
      get find_a_room_path, params: { per: "500" }, as: :json

      expect(response.parsed_body["pagination"]["per"]).to eq(100)
    end

    it "defaults to 30 per page with 30 entries on page 1" do
      get find_a_room_path, as: :json

      json = response.parsed_body
      expect(json["pagination"]["per"]).to eq(30)
      expect(json["rooms"].size).to eq(30)
    end

    it "returns the remainder on page 2" do
      get find_a_room_path, params: { page: "2" }, as: :json

      json = response.parsed_body
      expect(json["rooms"].size).to eq(5)
      expect(json["pagination"]["page"]).to eq(2)
      expect(json["pagination"]["pages"]).to eq(2)
      expect(json["pagination"]["count"]).to eq(35)
    end
  end

  describe "view=inactive_rooms" do
    let(:building) { create(:building, workspace: workspace) }
    let!(:not_in_feed_room) { create(:room, building: building, workspace: workspace, in_feed: false) }

    it "denies a viewer with a not_authorized redirect + alert, and never leaks the inactive room" do
      viewer = membership_with("viewer")
      sign_in(viewer)

      get find_a_room_path, params: { view: "inactive_rooms" }

      expect(response).to redirect_to(workspace_path(workspace))
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))

      follow_redirect!
      expect(response.body).not_to include(not_in_feed_room.display_name)
    end

    it "allows an admin to see the in_feed:false room" do
      admin = membership_with("admin")
      sign_in(admin)

      get find_a_room_path, params: { view: "inactive_rooms" }, as: :json

      ids = response.parsed_body["rooms"].map { |r| r["id"] }
      expect(ids).to include(not_in_feed_room.id)
    end
  end

  describe "view=inactive_buildings" do
    let(:hidden_building) { create(:building, :hidden, workspace: workspace) }
    let!(:room_in_hidden_building) { create(:room, building: hidden_building, workspace: workspace) }

    it "as admin returns 200 including a classroom in a hidden building" do
      admin = membership_with("admin")
      sign_in(admin)

      get find_a_room_path, params: { view: "inactive_buildings" }, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["rooms"].map { |r| r["id"] }
      expect(ids).to include(room_in_hidden_building.id)
    end

    it "denies a viewer" do
      viewer = membership_with("viewer")
      sign_in(viewer)

      get find_a_room_path, params: { view: "inactive_buildings" }

      expect(response).to redirect_to(workspace_path(workspace))
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
    end
  end

  describe "view=junk" do
    let(:viewer) { membership_with("viewer") }
    let(:building) { create(:building, workspace: workspace) }
    let!(:listed_classroom) { create(:room, building: building, workspace: workspace) }

    it "behaves as the active (default) view rather than erroring or denying" do
      sign_in(viewer)

      get find_a_room_path, params: { view: "junk" }, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["rooms"].map { |r| r["id"] }
      expect(ids).to eq([ listed_classroom.id ])
    end
  end
end
