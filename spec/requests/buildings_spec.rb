require "rails_helper"

# MiClassrooms Phase 4 Task 8 (Brief §5.3, §14.1): the admin Buildings
# section — index (FTS5 search over name/nickname/abbreviation, hidden
# toggle, pagination) and show (floors + read-only notes), both admin-only
# end to end (BuildingPolicy). Mirrors spec/requests/rooms_spec.rb's tenancy
# setup: shared-posture stub + workspace-scoped fixtures + sign_in, and reuses
# the "an admin-only action" shared example (spec/support/shared_examples/
# admin_only_action.rb) introduced by Task 7's room-edit spec.
RSpec.describe "GET /buildings", type: :request do
  let(:workspace) { create(:workspace, slug: "buildings-spec-workspace", personal: false) }

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

  let(:building) { create(:building, workspace: workspace, name: "Mason Hall") }
  let!(:classroom) { create(:room, building: building, workspace: workspace) }

  describe "as a non-admin viewer" do
    it_behaves_like "an admin-only action" do
      let(:actor) { membership_with("viewer") }
      let(:http_method) { :get }
      let(:request_path) { buildings_path }
    end
  end

  # BuildingPolicy denies ALL FOUR contract actions (index/show/edit/update)
  # to a non-admin. #edit/#update aren't real controller methods yet (Task 9
  # adds them) — routing a request there would raise
  # AbstractController::ActionNotFound before Pundit's `authorize` ever runs,
  # which isn't the "denied with a redirect + alert" shape the shared example
  # asserts, so those two are proven directly against the policy instead of
  # over HTTP (per the task brief).
  describe "BuildingPolicy for a non-admin" do
    it "denies edit? and update?" do
      viewer = membership_with("viewer")

      policy = BuildingPolicy.new(viewer, building)

      expect(policy.edit?).to be(false)
      expect(policy.update?).to be(false)
    end
  end

  describe "as an admin" do
    let(:admin) { membership_with("admin") }

    before { sign_in(admin) }

    it "returns 200 including a classroom-containing building" do
      get buildings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(building.display_name)
    end

    it "excludes a building with no classrooms" do
      empty_building = create(:building, workspace: workspace, name: "Empty Hall")

      get buildings_path

      expect(response.body).to include(building.display_name)
      expect(response.body).not_to include(empty_building.display_name)
    end

    it "excludes a building whose only rooms aren't classrooms" do
      office_building = create(:building, workspace: workspace, name: "Office Only Hall")
      create(:room, building: office_building, workspace: workspace, room_type: "Office")

      get buildings_path

      expect(response.body).not_to include(office_building.display_name)
    end

    it "excludes a hidden building by default, includes it with show_hidden=1" do
      hidden_building = create(:building, :hidden, workspace: workspace, name: "Hidden Hall")
      create(:room, building: hidden_building, workspace: workspace)

      get buildings_path
      expect(response.body).not_to include(hidden_building.display_name)

      get buildings_path, params: { show_hidden: "1" }
      expect(response.body).to include(hidden_building.display_name)
    end

    it "matches an abbreviation prefix via FTS5 search" do
      matching = create(:building, workspace: workspace, name: "North Quadrangle", abbreviation: "NQ")
      create(:room, building: matching, workspace: workspace)
      non_matching = create(:building, workspace: workspace, name: "South Hall", abbreviation: "SH")
      create(:room, building: non_matching, workspace: workspace)

      get buildings_path, params: { q: "NQ" }, as: :json

      ids = response.parsed_body["buildings"].map { |b| b["id"] }
      expect(ids).to include(matching.id)
      expect(ids).not_to include(non_matching.id)
    end

    # Regression for the review's Critical finding: `with_classrooms` (from
    # BuildingPolicy::Scope#resolve) and `Building.search_name` both filter on
    # the SAME `id` column via `where(id: ...)`. `scope.merge(search_name(q))`
    # OVERRIDES (does not AND) a duplicate equality/IN predicate on the
    # merging side, so the classroom filter was silently discarded whenever
    # `q` was present — a classroom-less building whose name/nickname/
    # abbreviation matched the term leaked into results. Fails against
    # `.merge`, passes against `.where(id: ...)`.
    it "excludes a classroom-less building whose name matches the search term (merge would leak it in)" do
      matching_with_classroom = create(:building, workspace: workspace, name: "Search Target Hall")
      create(:room, building: matching_with_classroom, workspace: workspace)
      matching_without_classroom = create(:building, workspace: workspace, name: "Search Target Annex")

      get buildings_path, params: { q: "Search Target" }, as: :json

      ids = response.parsed_body["buildings"].map { |b| b["id"] }
      expect(ids).to include(matching_with_classroom.id)
      expect(ids).not_to include(matching_without_classroom.id)
    end

    # Query-budget regression for the review's N+1 finding: Bullet only flags
    # unpreloaded ASSOCIATION lazy-loads, not a fresh `.count` on a
    # further-scoped relation — so `building.rooms.classroom.count` per row
    # (index_json + the HTML view) slipped past the green Bullet run as a
    # per-building COUNT query. Post-fix, one grouped `Room.classroom
    # .where(building_id: ...).group(:building_id).count` replaces all of
    # them. Fails against the per-row `.count` (6 queries: the 5 seeded here
    # plus the outer `let!(:building)`), passes against the grouped count
    # (1 query total, regardless of building count).
    it "does not scale the classroom-count query with the number of buildings on the page" do
      create_list(:building, 5, workspace: workspace).each do |b|
        create(:room, building: b, workspace: workspace)
      end

      # Two distinct shapes, matched separately so Pagy's own `scope.count`
      # (a COUNT on "buildings" whose WHERE clause happens to embed a rooms
      # sub-select, via `with_classrooms`) doesn't get miscounted as a
      # per-row rooms query: the pre-fix per-row query filters on a single
      # `"rooms"."building_id" = ?`; the post-fix batched query is a single
      # `GROUP BY "rooms"."building_id"` aggregate.
      per_row_count_queries = 0
      grouped_count_queries = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        next if %w[CACHE SCHEMA].include?(payload[:name])
        sql = payload[:sql]
        per_row_count_queries += 1 if sql.match?(/SELECT COUNT\(\*\) FROM "rooms" WHERE "rooms"\."building_id" = \?/i)
        grouped_count_queries += 1 if sql.match?(/GROUP BY "rooms"\."building_id"/i)
      end

      begin
        get buildings_path
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(response).to have_http_status(:ok)
      expect(per_row_count_queries).to eq(0)
      expect(grouped_count_queries).to eq(1)
    end

    it "paginates results" do
      create_list(:building, 25, workspace: workspace).each do |b|
        create(:room, building: b, workspace: workspace)
      end

      get buildings_path, as: :json
      first_page = response.parsed_body
      expect(first_page["buildings"].size).to eq(20)
      expect(first_page["page"]).to eq(1)
      expect(first_page["pages"]).to eq(2)

      get buildings_path, params: { page: "2" }, as: :json
      second_page = response.parsed_body
      # 25 seeded + the outer `let!(:classroom)`'s building = 26 total.
      expect(second_page["buildings"].size).to eq(6)
      expect(second_page["page"]).to eq(2)
    end

    it "renders the index JSON shape" do
      other_campus = create(:campus, workspace: workspace, description: "North Campus")
      building.update!(campus: other_campus, nickname: "The Mason", abbreviation: "MH")

      get buildings_path, as: :json

      json = response.parsed_body
      expect(json.keys).to match_array(%w[buildings page pages])

      entry = json["buildings"].find { |b| b["id"] == building.id }
      expect(entry.keys).to match_array(
        %w[id bldrecnbr name nickname abbreviation campus classroom_count hidden]
      )
      expect(entry["bldrecnbr"]).to eq(building.bldrecnbr)
      expect(entry["name"]).to eq(building.name)
      expect(entry["nickname"]).to eq("The Mason")
      expect(entry["abbreviation"]).to eq("MH")
      expect(entry["campus"]).to eq("North Campus")
      expect(entry["classroom_count"]).to eq(1)
      expect(entry["hidden"]).to be(false)
    end
  end
end

# MiClassrooms Phase 4 Task 8 (Brief §5.3, §14.1): building detail — HTML +
# JSON, floors (with a representative classroom's floor-plan link), and
# read-only notes. Sibling top-level example group (not nested above),
# mirroring rooms_spec.rb's "GET /rooms/:id" split.
RSpec.describe "GET /buildings/:id", type: :request do
  let(:workspace) { create(:workspace, slug: "buildings-show-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  let(:building) { create(:building, workspace: workspace, name: "Mason Hall") }
  let!(:classroom) { create(:room, building: building, workspace: workspace) }

  describe "as a non-admin viewer" do
    it_behaves_like "an admin-only action" do
      let(:actor) { membership_with("viewer") }
      let(:http_method) { :get }
      let(:request_path) { building_path(building) }
    end
  end

  describe "as an admin" do
    let(:admin) { membership_with("admin") }

    before { sign_in(admin) }

    it "returns 200 for a hidden building instead of denying" do
      hidden_building = create(:building, :hidden, workspace: workspace)

      get building_path(hidden_building), as: :json

      expect(response).to have_http_status(:ok)
    end

    it "renders the show JSON shape: building fields, address, floors, photo_url" do
      floor_with_plan = create(:floor, building: building, workspace: workspace, label: "1")
      floor_without_plan = create(:floor, building: building, workspace: workspace, label: "2")
      classroom.update!(floor: floor_with_plan)
      floor_with_plan.plan.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "floor-1.png", content_type: "image/png"
      )
      building.photo.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "mason.png", content_type: "image/png"
      )
      building.update!(address: "419 S State St", city: "Ann Arbor", state: "MI", zip: "48109", country: "USA")

      get building_path(building), as: :json

      json = response.parsed_body
      expect(json["id"]).to eq(building.id)
      expect(json["bldrecnbr"]).to eq(building.bldrecnbr)
      expect(json["name"]).to eq(building.name)
      expect(json["address"]).to eq("419 S State St")
      expect(json["city"]).to eq("Ann Arbor")
      expect(json["full_address"]).to eq(building.full_address)
      expect(json["photo_url"]).to be_present

      floors = json["floors"]
      expect(floors.size).to eq(2)

      with_plan = floors.find { |f| f["id"] == floor_with_plan.id }
      expect(with_plan["label"]).to eq("1")
      expect(with_plan["plan_url"]).to be_present
      expect(with_plan["classroom_count"]).to eq(1)

      without_plan = floors.find { |f| f["id"] == floor_without_plan.id }
      expect(without_plan["plan_url"]).to be_nil
      expect(without_plan["classroom_count"]).to eq(0)
    end

    it "renders photo_url as nil when no photo is attached" do
      get building_path(building), as: :json

      expect(response.parsed_body["photo_url"]).to be_nil
    end

    it "renders the floors list with a link to a representative classroom's floor plan" do
      floor = create(:floor, building: building, workspace: workspace, label: "3")
      classroom.update!(floor: floor)

      get building_path(building)

      expect(response.body).to include(floor_plan_room_path(classroom))
    end

    it "renders read-only notes for the building" do
      note = create(:note, notable: building, workspace: workspace)

      get building_path(building)

      expect(response.body).to include(note.body.to_plain_text)
    end

    # Query-budget regression for the review's N+1 finding: the HTML view
    # re-queried `@building.floors.order(:label)` from scratch (a SEPARATE,
    # non-preloaded collection from the one `show_json` builds), then fired
    # `floor.rooms.classroom.first` (representative-room link) and
    # `floor.rooms.classroom.count` (buildings_helper) per floor — neither
    # caught by Bullet, since both are further-scoped `.first`/`.count`
    # calls on a loaded record, not unpreloaded association lazy-loads.
    # Post-fix, `@floors` is loaded ONCE and both the per-floor count and the
    # representative-room lookup are each a single batched query. Fails
    # against the per-floor calls (5 queries apiece, one per floor seeded
    # below), passes against the batched queries (1 apiece, regardless of
    # floor count).
    it "does not scale per-floor queries with the number of floors on the page" do
      floors = create_list(:floor, 5, building: building, workspace: workspace)
      floors.each { |f| create(:room, building: building, workspace: workspace, floor: f) }

      room_count_queries = 0
      room_select_queries = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        next if %w[CACHE SCHEMA].include?(payload[:name])
        sql = payload[:sql]
        room_count_queries += 1 if sql.match?(/SELECT COUNT\(\*\).*FROM "rooms"/i)
        room_select_queries += 1 if sql.match?(/SELECT "rooms"\.\* FROM "rooms"/i)
      end

      begin
        get building_path(building)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(response).to have_http_status(:ok)
      expect(room_count_queries).to eq(1)
      expect(room_select_queries).to eq(1)
    end
  end
end
