require "rails_helper"

RSpec.describe ActivityLog::Range do
  let(:zone) { ActiveSupport::TimeZone["Europe/Amsterdam"] }

  around { |ex| travel_to(Time.utc(2026, 9, 17, 12, 0, 0)) { ex.run } }

  it "defaults to the last 30 days, from the start of that day in the zone" do
    range = described_class.resolve(key: nil, from: nil, to: nil, zone: zone)
    expect(range.key).to eq("30d")
    expect(range).to be_bounded
    expect(range.from).to eq(zone.parse("2026-08-18 00:00:00"))
    expect(range.to).to eq(zone.now)
  end

  it "resolves the presets" do
    expect(described_class.resolve(key: "24h", from: nil, to: nil, zone: zone).from).to eq(zone.now - 24.hours)
    expect(described_class.resolve(key: "7d", from: nil, to: nil, zone: zone).from).to eq(zone.parse("2026-09-10 00:00:00"))
    expect(described_class.resolve(key: "all", from: nil, to: nil, zone: zone)).not_to be_bounded
  end

  it "reads a custom range inclusively in the zone and swaps inverted bounds" do
    range = described_class.resolve(key: "custom", from: "2026-09-17", to: "2026-09-03", zone: zone)
    expect(range).to be_custom
    expect(range.from).to eq(zone.parse("2026-09-03 00:00:00"))
    expect(range.to).to eq(zone.parse("2026-09-17 23:59:59.999999999"))
    expect(range.from_date).to eq(Date.new(2026, 9, 3))
  end

  it "falls back to the default on an unknown key or an unparseable custom date" do
    expect(described_class.resolve(key: "yesterday", from: nil, to: nil, zone: zone).key).to eq("30d")
    expect(described_class.resolve(key: "custom", from: "nope", to: "2026-09-17", zone: zone).key).to eq("30d")
    expect(described_class.resolve(key: "custom", from: nil, to: nil, zone: zone).key).to eq("30d")
  end
end
