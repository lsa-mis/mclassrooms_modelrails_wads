require "rails_helper"

# Task 7 of planning/plans/phase-2-ingestion.md: Sync::UpdateCampuses is the
# FIRST concrete Sync::BasePhase subclass and the exemplar the remaining five
# phases (buildings, rooms, facility_ids, characteristics, contacts — Tasks
# 8-11) are expected to mirror, so this spec drives it through a REAL
# UmApi::Client (stubbed via WebMock, same as client_spec.rb) rather than a
# fake — proving the phase, the gateway client, and BasePhase's lifecycle all
# integrate correctly, not just that #perform's Ruby is right in isolation.
#
# ENV setup mirrors spec/lib/um_api/client_spec.rb's `around` block exactly:
# Client#build_uri reads UM_API_BASE_URL with no fallback and TokenCache
# reads UM_API_TOKEN_URL the same way.
#
# Current.workspace: Campus is Tenanted, and Tenanted installs no
# default_scope (app/docs/developer/extending.md) — #perform scopes every
# Campus query through .for_current_workspace itself, but nothing here (nor
# in BasePhase) sets Current.workspace. In production that's the pipeline
# job's job (Task 12); until then, every spec below sets Current.workspace to
# the run's workspace explicitly, exactly like spec/support/shared_examples/
# tenanted_directory_record.rb does for every other Tenanted model spec.
RSpec.describe Sync::UpdateCampuses do
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
  end

  def phase = run.sync_phases.find_by!(key: "campuses")

  # BasePhase's counters hash is a Hash.new(0) that only gains a key once
  # #count actually increments it (see app/lib/sync/base_phase.rb) — an
  # untouched counter is simply ABSENT, not present-and-zero. #fetch(...,
  # 0) asserts "this counter is effectively zero" the same way whether the
  # phase never touched it at all or (hypothetically) touched it and net
  # zero, so these assertions have teeth either way.
  def counter(phase, key) = phase.counters.fetch(key.to_s, 0)

  describe "a first run against an empty workspace" do
    it "creates every campus from the feed and reports accurate counters" do
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json",
        query: { "$start_index" => "0", "$count" => "1000" })

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(Campus.for_current_workspace.count).to eq(2)

      ann_arbor = Campus.for_current_workspace.find_by!(code: "100")
      expect(ann_arbor.description).to eq("Ann Arbor Central")
      michigan_medicine = Campus.for_current_workspace.find_by!(code: "250")
      expect(michigan_medicine.description).to eq("Michigan Medicine")

      expect(phase).to be_succeeded
      expect(phase.counters).to include("created" => 2, "api_calls" => 1, "rate_limit_sleeps" => 0)
      expect(counter(phase, :updated)).to eq(0)
      expect(counter(phase, :deleted)).to eq(0)
    end

    # A brand-new Campus must land in the run's workspace, not merely be
    # findable through it — the load-bearing tenant-isolation assertion this
    # exemplar is judged on: an unscoped Campus.find_or_initialize_by(code:)
    # would still pass the count/description assertions above (single
    # workspace, no collision) but would fail THIS one.
    it "stamps new campuses with the run's workspace" do
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json",
        query: { "$start_index" => "0", "$count" => "1000" })

      described_class.call(run: run, client: client)

      expect(Campus.find_by!(code: "100").workspace).to eq(workspace)
    end
  end

  describe "a second run with one changed description" do
    it "updates only the changed campus and counts it, leaving the unchanged one alone" do
      create(:campus, workspace: workspace, code: "100", description: "Stale Name")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json",
        query: { "$start_index" => "0", "$count" => "1000" })

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(Campus.for_current_workspace.find_by!(code: "100").description).to eq("Ann Arbor Central")
      expect(phase.counters).to include("created" => 1, "updated" => 1)
    end

    it "does not count a no-op update when the fetched row is identical to what's already stored" do
      create(:campus, workspace: workspace, code: "100", description: "Ann Arbor Central")
      create(:campus, workspace: workspace, code: "250", description: "Michigan Medicine")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json",
        query: { "$start_index" => "0", "$count" => "1000" })

      described_class.call(run: run, client: client)

      expect(counter(phase, :created)).to eq(0)
      expect(counter(phase, :updated)).to eq(0)
    end
  end

  describe "idempotency" do
    it "reports 0 created/updated/deleted on a second run against the same feed" do
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json",
        query: { "$start_index" => "0", "$count" => "1000" })

      described_class.call(run: run, client: client)
      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(counter(phase, :created)).to eq(0)
      expect(counter(phase, :updated)).to eq(0)
      expect(counter(phase, :deleted)).to eq(0)
      expect(Campus.for_current_workspace.count).to eq(2)
    end
  end

  describe "hard-delete of a campus that dropped out of the feed" do
    it "destroys an unreferenced pre-existing campus absent from the fixture and counts it" do
      create(:campus, workspace: workspace, code: "999", description: "Retired Campus")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json",
        query: { "$start_index" => "0", "$count" => "1000" })

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(Campus.for_current_workspace.exists?(code: "999")).to be false
      expect(phase.counters).to include("deleted" => 1)
      expect(phase).to be_succeeded
    end

    # THE Critical this fix exists for: campuses sync BEFORE buildings, so a
    # retiring campus that dropped out of the feed still has last run's
    # buildings pointing at it (buildings.campus_id FK, enforced by SQLite).
    # `stale.destroy!` therefore raises ActiveRecord::InvalidForeignKey on
    # the NORMAL retirement case. That must NOT abort the phase (which would
    # halt Task 12's whole pipeline): the still-referenced campus is
    # skipped-with-warning, the phase still SUCCEEDS, and it is NOT counted
    # as deleted (the counter reflects only ACTUAL deletions).
    it "skips a still-referenced campus with a warning instead of failing the phase" do
      stale = create(:campus, workspace: workspace, code: "999", description: "Retiring Campus")
      create(:building, workspace: workspace, campus: stale)
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json",
        query: { "$start_index" => "0", "$count" => "1000" })

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(phase).to be_succeeded
      expect(Campus.for_current_workspace.exists?(code: "999")).to be true
      expect(counter(phase, :deleted)).to eq(0)
      expect(phase.warnings).to include(a_string_matching(/999/))
    end

    # Mixed batch: the still-referenced campus is skipped-with-warning while
    # the unreferenced one is genuinely deleted in the SAME sweep — proving
    # per-record resilience (one bad delete doesn't poison the others) and
    # that count(:deleted) counts only the one that actually went.
    it "deletes the unreferenced stale campus but not the referenced one in the same run" do
      referenced = create(:campus, workspace: workspace, code: "999", description: "Referenced")
      create(:building, workspace: workspace, campus: referenced)
      create(:campus, workspace: workspace, code: "888", description: "Unreferenced")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json",
        query: { "$start_index" => "0", "$count" => "1000" })

      described_class.call(run: run, client: client)

      expect(Campus.for_current_workspace.exists?(code: "999")).to be true
      expect(Campus.for_current_workspace.exists?(code: "888")).to be false
      expect(phase.counters).to include("deleted" => 1)
      expect(phase.warnings).to include(a_string_matching(/999/))
    end

    # Tenant-safety teeth: a campus in ANOTHER workspace, absent from THIS
    # feed, must never be touched by this run — an unscoped
    # Campus.where.not(code: seen) would destroy it too.
    it "never deletes a same-codeless campus belonging to a different workspace" do
      other_workspace = create(:workspace)
      untouchable = create(:campus, workspace: other_workspace, code: "999", description: "Someone else's campus")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json",
        query: { "$start_index" => "0", "$count" => "1000" })

      described_class.call(run: run, client: client)

      expect(untouchable.reload).to be_persisted
    end
  end

  # Empty-seen guard: a transient API glitch returning zero rows must NOT be
  # read as "every campus was retired" and wipe the table. The sweep is
  # skipped entirely with a warning; the phase still succeeds.
  describe "an empty feed" do
    it "deletes nothing and warns instead of wiping every pre-existing campus" do
      create(:campus, workspace: workspace, code: "100", description: "Ann Arbor Central")
      create(:campus, workspace: workspace, code: "250", description: "Michigan Medicine")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses_empty.json",
        query: { "$start_index" => "0", "$count" => "1000" })

      result = nil
      expect { result = described_class.call(run: run, client: client) }
        .not_to change(Campus, :count)

      expect(result).to be_success
      expect(phase).to be_succeeded
      expect(counter(phase, :deleted)).to eq(0)
      expect(phase.warnings).to include(a_string_matching(/zero rows/i))
    end
  end

  describe "dry run" do
    it "deletes nothing but still reports the count Campus records unchanged" do
      dry_run = create(:sync_run, workspace: workspace, dry_run: true)
      create(:campus, workspace: workspace, code: "100", description: "Ann Arbor Central")
      create(:campus, workspace: workspace, code: "250", description: "Michigan Medicine")
      create(:campus, workspace: workspace, code: "999", description: "Retired Campus")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json",
        query: { "$start_index" => "0", "$count" => "1000" })

      result = nil
      expect { result = described_class.call(run: dry_run, client: client) }
        .not_to change(Campus, :count)

      expect(result).to be_success
      expect(Campus.for_current_workspace.exists?(code: "999")).to be true

      dry_phase = dry_run.sync_phases.find_by!(key: "campuses")
      expect(dry_phase.counters).to include("deleted" => 1)
      expect(counter(dry_phase, :created)).to eq(0)
      expect(counter(dry_phase, :updated)).to eq(0)
      expect(dry_phase).to be_succeeded
    end
  end
end
