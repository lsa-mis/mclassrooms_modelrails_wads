require "rails_helper"

# Task 8 of planning/plans/phase-2-ingestion.md: Sync::UpdateBuildings mirrors
# Sync::UpdateCampuses's shape (Task 7 — real UmApi::Client stubbed via
# WebMock, Current.workspace set explicitly per spec/support/
# shared_examples/tenanted_directory_record.rb's convention) with three
# structural differences this file is built to pin:
#
# 1. Scope filtering via SyncScopeRule (phase 1 model): a row passes when
#    (its campus code is campus_allow-listed OR its own bldrecnbr is
#    building_allow-listed) AND its bldrecnbr is NOT building_exclude-listed
#    (Brief §6.1/§8.2). building_info_page1.json (campus "100": MLB, Angell
#    Hall) and building_info_page2.json (campus "250": DEDC) give one allowed
#    and one excluded-by-default campus to filter between.
# 2. Warn-only absence (Brief §8.4) — buildings NEVER get hard-deleted
#    (campuses, Task 7) or deactivated (rooms, Task 10): a building missing
#    from the feed produces a warning naming its bldrecnbr and is otherwise
#    untouched (in_feed stays whatever it already was). Scope-filtered-out
#    buildings are NOT "absent" — they were genuinely returned by the feed,
#    just not ingested by this workspace's config — so absence-tracking
#    must be computed from the RAW feed, before scope filtering.
# 3. Newly CREATED buildings enqueue GeocodeBuildingJob; updates never do.
#
# Note on dry_run: per BasePhase's contract (and Sync::UpdateCampuses's own
# header comment), `guarded_write` wraps only a phase's DESTRUCTIVE write;
# the routine create/update upsert always runs unconditionally regardless
# of dry_run. Buildings have no destructive write at all (warn-only), so
# dry_run has no special-cased behavior here worth pinning — there is
# nothing to preview that differs from a real run.
#
# Endpoint: "/bf/Buildings/v2/BuildingInfo" (sync-fix Task 2) — confirmed
# against live credentialed access (see the proven reference
# `lib/tasks/um_import.rake`), scope "buildings", NO fiscal-year param.
# Paged via `UmApi::Client#fetch_all` (sync-fix Task 1): real
# `$start_index`/`$count` query params, real two-level envelope
# (`resp["ListOfBldgs"]["Buildings"]`). building_info_page1.json carries the
# two campus-100 buildings (MLB, Angell Hall) padded with campus-999 filler
# rows out to exactly 1000 entries so fetch_all's "short page stops the
# loop" rule genuinely forces a second request; building_info_page2.json
# carries the single campus-250 building (DEDC) that request returns.
RSpec.describe Sync::UpdateBuildings do
  around do |example|
    original = %w[UM_API_BASE_URL UM_API_TOKEN_URL UM_API_CLIENT_ID UM_API_CLIENT_SECRET].index_with { |key| ENV[key] }

    ENV["UM_API_BASE_URL"] = UmApiStubs::DEFAULT_BASE_URL
    ENV["UM_API_TOKEN_URL"] = UmApiStubs::DEFAULT_TOKEN_URL
    ENV["UM_API_CLIENT_ID"] = "test-client"
    ENV["UM_API_CLIENT_SECRET"] = "test-secret"

    example.run

    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  let(:workspace) { create(:workspace) }
  let(:run) { create(:sync_run, workspace: workspace) }
  let(:client) { UmApi::Client.new }

  before do
    Current.workspace = workspace
    stub_um_token(scope: "buildings")
    # Every SyncScopeRule's `value` is a plain string; campus 100 is the
    # in-scope campus for every example below unless a test overrides it.
    create(:sync_scope_rule, workspace: workspace, rule_type: "campus_allow", value: "100")
  end

  def phase = run.sync_phases.find_by!(key: "buildings")

  # See update_campuses_spec.rb's identical helper: an untouched counter is
  # ABSENT from the hash, not present-and-zero, so #fetch(..., 0) has teeth
  # either way.
  def counter(phase, key) = phase.counters.fetch(key.to_s, 0)

  def stub_buildings_feed
    page1_stub = stub_um_get("/bf/Buildings/v2/BuildingInfo", fixture: "building_info_page1.json",
      query: { "$start_index" => "0", "$count" => "1000" })
    stub_um_get("/bf/Buildings/v2/BuildingInfo", fixture: "building_info_page2.json",
      query: { "$start_index" => "1000", "$count" => "1000" })
    page1_stub
  end

  describe "a first run against an empty workspace" do
    it "creates only the campus-100 buildings and reports accurate counters" do
      stub_buildings_feed

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(Building.for_current_workspace.pluck(:bldrecnbr)).to contain_exactly("1005046", "1005090")

      mlb = Building.for_current_workspace.find_by!(bldrecnbr: "1005046")
      expect(mlb.name).to eq("Modern Languages Building")
      expect(mlb.abbreviation).to eq("MLB")
      expect(mlb.address).to eq("812 E Washington St")
      expect(mlb.city).to eq("Ann Arbor")
      expect(mlb.state).to eq("MI")
      expect(mlb.zip).to eq("48109")
      expect(mlb.country).to eq("USA")
      expect(mlb.in_feed).to be true

      expect(phase).to be_succeeded
      expect(phase.counters).to include("created" => 2)
      expect(counter(phase, :updated)).to eq(0)
    end

    it "stamps a new building with the local Campus matching its BuildingCampusCode" do
      campus = create(:campus, workspace: workspace, code: "100")
      stub_buildings_feed

      described_class.call(run: run, client: client)

      expect(Building.for_current_workspace.find_by!(bldrecnbr: "1005046").campus).to eq(campus)
    end

    it "excludes a building whose campus is not campus_allow-listed" do
      stub_buildings_feed

      described_class.call(run: run, client: client)

      expect(Building.for_current_workspace.exists?(bldrecnbr: "1005200")).to be false
    end

    it "includes a campus-250 building anyway when it is building_allow-listed" do
      create(:sync_scope_rule, workspace: workspace, rule_type: "building_allow", value: "1005200")
      stub_buildings_feed

      described_class.call(run: run, client: client)

      expect(Building.for_current_workspace.exists?(bldrecnbr: "1005200")).to be true
    end

    it "still excludes a building_exclude-listed bldrecnbr even though its campus is allowed" do
      create(:sync_scope_rule, workspace: workspace, rule_type: "building_exclude", value: "1005046")
      stub_buildings_feed

      described_class.call(run: run, client: client)

      expect(Building.for_current_workspace.exists?(bldrecnbr: "1005046")).to be false
      expect(Building.for_current_workspace.exists?(bldrecnbr: "1005090")).to be true
    end

    it "building_exclude wins even when the same bldrecnbr is ALSO building_allow-listed" do
      create(:sync_scope_rule, workspace: workspace, rule_type: "building_allow", value: "1005200")
      create(:sync_scope_rule, workspace: workspace, rule_type: "building_exclude", value: "1005200")
      stub_buildings_feed

      described_class.call(run: run, client: client)

      expect(Building.for_current_workspace.exists?(bldrecnbr: "1005200")).to be false
    end

    it "enqueues GeocodeBuildingJob only for buildings actually created" do
      stub_buildings_feed

      expect { described_class.call(run: run, client: client) }
        .to have_enqueued_job(GeocodeBuildingJob).exactly(2).times
    end
  end

  describe "a second run with one changed field" do
    it "updates only the changed building, counts it, and does not enqueue geocoding for an update" do
      create(:building, workspace: workspace, bldrecnbr: "1005046", name: "Stale Name",
        abbreviation: "MLB", address: "812 E Washington St", city: "Ann Arbor", state: "MI",
        zip: "48109", country: "USA", in_feed: true)
      create(:building, workspace: workspace, bldrecnbr: "1005090", name: "Angell Hall",
        abbreviation: "AH", address: "435 S State St", city: "Ann Arbor", state: "MI",
        zip: "48109", country: "USA", in_feed: true)
      stub_buildings_feed

      result = nil
      expect { result = described_class.call(run: run, client: client) }
        .not_to have_enqueued_job(GeocodeBuildingJob)

      expect(result).to be_success
      expect(Building.for_current_workspace.find_by!(bldrecnbr: "1005046").name).to eq("Modern Languages Building")
      expect(counter(phase, :created)).to eq(0)
      expect(phase.counters).to include("updated" => 1)
    end

    it "does not count a no-op update when the fetched row matches what's already stored" do
      create(:building, workspace: workspace, bldrecnbr: "1005046", name: "Modern Languages Building",
        abbreviation: "MLB", address: "812 E Washington St", city: "Ann Arbor", state: "MI",
        zip: "48109", country: "USA", in_feed: true)
      create(:building, workspace: workspace, bldrecnbr: "1005090", name: "Angell Hall",
        abbreviation: "AH", address: "435 S State St", city: "Ann Arbor", state: "MI",
        zip: "48109", country: "USA", in_feed: true)
      stub_buildings_feed

      described_class.call(run: run, client: client)

      expect(counter(phase, :created)).to eq(0)
      expect(counter(phase, :updated)).to eq(0)
    end
  end

  describe "idempotency" do
    it "reports 0 created/updated on a second run against the same feed" do
      stub_buildings_feed
      described_class.call(run: run, client: client)
      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(counter(phase, :created)).to eq(0)
      expect(counter(phase, :updated)).to eq(0)
      expect(Building.for_current_workspace.count).to eq(2)
    end
  end

  describe "D6: hidden_at is never touched by sync" do
    it "leaves a hidden building's hidden_at intact after an update" do
      hidden_building = create(:building, :hidden, workspace: workspace, bldrecnbr: "1005046", name: "Old Name")
      original_hidden_at = hidden_building.hidden_at
      stub_buildings_feed

      described_class.call(run: run, client: client)

      reloaded = hidden_building.reload
      expect(reloaded.name).to eq("Modern Languages Building")
      expect(reloaded.hidden_at).to be_within(1.second).of(original_hidden_at)
    end
  end

  describe "warn-only absence (Brief §8.4) — buildings are never deleted or deactivated" do
    it "warns naming the bldrecnbr for a pre-existing building absent from the feed, without deleting or flipping in_feed" do
      absent = create(:building, workspace: workspace, bldrecnbr: "9999999", name: "Demolished Hall", in_feed: true)
      stub_buildings_feed

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(Building.for_current_workspace.exists?(id: absent.id)).to be true
      expect(absent.reload.in_feed).to be true
      expect(phase.warnings).to include(a_string_matching(/9999999/))
    end

    it "does not warn about a building that is present in the feed but filtered out by scope rules" do
      # 1005200 (campus 250) IS genuinely present in the upstream feed (page
      # 2), just out of scope by default (only campus 100 is
      # campus_allow-listed here) — it must be recognized as "in the feed"
      # for absence purposes even though this workspace doesn't ingest it,
      # or every run would wrongly warn about it. Its pre-existing local
      # row (simulating "previously allowed, since excluded") must also be
      # left untouched — filtered out, not updated.
      pre_existing = create(:building, workspace: workspace, bldrecnbr: "1005200", name: "Old DEDC Name", in_feed: true)
      stub_buildings_feed

      described_class.call(run: run, client: client)

      expect(phase.warnings).not_to include(a_string_matching(/1005200/))
      expect(pre_existing.reload.name).to eq("Old DEDC Name")
    end

    it "emits one summary warning instead of one per building when the feed returns zero rows" do
      create(:building, workspace: workspace, bldrecnbr: "1005046", in_feed: true)
      create(:building, workspace: workspace, bldrecnbr: "1005090", in_feed: true)
      stub_um_get("/bf/Buildings/v2/BuildingInfo", fixture: "building_info_empty.json",
        query: { "$start_index" => "0", "$count" => "1000" })

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(phase).to be_succeeded
      expect(phase.warnings.size).to eq(1)
      expect(phase.warnings).to include(a_string_matching(/zero rows/i))
    end
  end
end
