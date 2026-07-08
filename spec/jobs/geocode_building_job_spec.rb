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
end
