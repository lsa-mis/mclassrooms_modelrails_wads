require "rails_helper"

# Task 8 of planning/plans/phase-2-ingestion.md: GeocodeBuildingJob is
# enqueued by Sync::UpdateBuildings for every newly-created building. No
# real network calls happen here — `Geocoder.search` is stubbed throughout
# (WebMock also globally blocks unstubbed network in spec/rails_helper.rb).
#
# Current.workspace: Building is Tenanted (no default_scope — app/docs/
# developer/extending.md), so per the template's job rule (CLAUDE.md
# deviation #1: "jobs must establish workspace context explicitly"), the
# job sets Current.workspace = building.workspace itself before doing
# anything tenant-scoped, rather than relying on ambient state a job
# runner would never have.
RSpec.describe GeocodeBuildingJob, type: :job do
  let(:building) { create(:building, address: "812 E Washington St", city: "Ann Arbor", state: "MI", zip: "48109") }

  def geocoder_result(lat:, lng:)
    double("Geocoder::Result", latitude: lat, longitude: lng) # rubocop:disable RSpec/VerifiedDoubles
  end

  it "geocodes the building's full address and writes latitude/longitude" do
    allow(Geocoder).to receive(:search)
      .with(building.full_address)
      .and_return([ geocoder_result(lat: 42.2808, lng: -83.7430) ])

    described_class.new.perform(building.id)

    building.reload
    expect(building.latitude).to eq(42.2808)
    expect(building.longitude).to eq(-83.7430)
  end

  it "skips geocoding entirely when the building already has coordinates" do
    building.update!(latitude: 1.0, longitude: 2.0)
    expect(Geocoder).not_to receive(:search)

    described_class.new.perform(building.id)

    building.reload
    expect(building.latitude).to eq(1.0)
    expect(building.longitude).to eq(2.0)
  end

  it "does nothing when the geocoder returns no results" do
    allow(Geocoder).to receive(:search).and_return([])

    described_class.new.perform(building.id)

    building.reload
    expect(building.latitude).to be_nil
    expect(building.longitude).to be_nil
  end

  it "sets Current.workspace to the building's workspace before geocoding" do
    seen_workspace = nil
    allow(Geocoder).to receive(:search) do
      seen_workspace = Current.workspace
      []
    end

    described_class.new.perform(building.id)

    expect(seen_workspace).to eq(building.workspace)
  end

  # Rails 8.1's activejob REMOVED the old :exponentially_longer wait
  # algorithm — ActiveJob::Exceptions#determine_delay only recognizes
  # :polynomially_longer now, so `retry_on ..., wait: :exponentially_longer`
  # fell through to `raise "Couldn't determine a delay based on
  # :exponentially_longer"` the moment a real Geocoder::Error/Timeout::Error
  # was raised — a RuntimeError from determine_delay ITSELF, inside the
  # retry_on rescue handler, not a backed-off retry.
  # `described_class.new.perform(building.id)` (used by every example above)
  # calls the plain method directly and bypasses ActiveJob's
  # rescue_from/retry_on wrapping entirely, which is exactly why this
  # survived: only `perform_later` + `perform_enqueued_jobs` exercises
  # retry_on for real.
  #
  # Geocoder.search is stubbed to raise ONCE then succeed (not on every
  # call): ActiveJob::TestHelper's perform_enqueued_jobs sets BOTH
  # perform_enqueued_jobs AND perform_enqueued_at_jobs, so a retry_job'd
  # re-enqueue (even with a future `wait:`) is executed immediately within
  # the same block rather than merely sitting in the queue. A stub that
  # raises unconditionally would exhaust all 3 configured attempts inside
  # that single block and legitimately re-raise the original error by
  # design (retry_on's documented "let it bubble up once attempts run out")
  # — that's correct behavior, not the bug this spec targets, so it would
  # give a false positive either way. Raising exactly once and then
  # succeeding isolates the ONE thing this fix is about: does the first
  # retry's delay computation blow up, or does the job quietly back off and
  # complete on its second attempt.
  describe "retry_on Geocoder::Error/Timeout::Error (wait: :polynomially_longer)" do
    include ActiveJob::TestHelper

    it "backs off and completes on retry instead of raising the delay-determination error, for Geocoder::Error" do
      call_count = 0
      allow(Geocoder).to receive(:search) do
        call_count += 1
        raise Geocoder::Error, "temporary lookup failure" if call_count == 1

        [ geocoder_result(lat: 42.2808, lng: -83.7430) ]
      end

      expect {
        perform_enqueued_jobs { described_class.perform_later(building.id) }
      }.not_to raise_error

      expect(call_count).to eq(2)
      building.reload
      expect(building.latitude).to eq(42.2808)
      expect(building.longitude).to eq(-83.7430)
    end

    it "backs off and completes on retry instead of raising the delay-determination error, for Timeout::Error" do
      call_count = 0
      allow(Geocoder).to receive(:search) do
        call_count += 1
        raise Timeout::Error, "network timeout" if call_count == 1

        []
      end

      expect {
        perform_enqueued_jobs { described_class.perform_later(building.id) }
      }.not_to raise_error

      expect(call_count).to eq(2)
    end
  end
end
