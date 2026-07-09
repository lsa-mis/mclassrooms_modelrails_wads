require "rails_helper"

RSpec.describe CharacteristicFilterGroups do
  let(:workspace) { create(:workspace) }
  let(:building)  { create(:building, workspace: workspace) }
  let(:room)      { create(:room, workspace: workspace, building: building) }

  before { Current.workspace = workspace }

  # Every characteristic is attached to `room` unless a test needs another
  # one; `code` auto-increments per the factory, so short_code is the only
  # thing that needs to vary.
  def characteristic(short_code:, description:, long_description: nil, room: self.room)
    create(:room_characteristic, room: room, short_code: short_code,
                                  description: description, long_description: long_description)
  end

  def rule(short_code:, **attrs)
    create(:characteristic_display_rule, workspace: workspace, short_code: short_code, **attrs)
  end

  describe ".filters" do
    it "parses 'Category: Value' into a group named by the category, labeled by the value" do
      characteristic(short_code: "seatmove", description: "Seating: Movable")

      group = described_class.filters.find { |g| g.name == "Seating" }

      expect(group).not_to be_nil
      expect(group.entries.map(&:short_code)).to eq([ "seatmove" ])
      expect(group.entries.map(&:label)).to eq([ "Movable" ])
    end

    it "buckets a description with no ':' into Other, which sorts last" do
      characteristic(short_code: "seatmove", description: "Seating: Movable")
      characteristic(short_code: "misc1", description: "Miscellaneous Feature")

      groups = described_class.filters

      expect(groups.last.name).to eq("Other")
      expect(groups.last.entries.map(&:label)).to eq([ "Miscellaneous Feature" ])
    end

    it "lets category_override beat the parsed category" do
      characteristic(short_code: "avoverride", description: "Seating: Special")
      rule(short_code: "avoverride", category_override: "Audio/Visual")

      names = described_class.filters.map(&:name)

      expect(names).to include("Audio/Visual")
      expect(names).not_to include("Seating")
    end

    it "collects team_learning rules into 'Team Based Learning' regardless of parsed category or category_override" do
      characteristic(short_code: "teamx", description: "Seating: TeamDesks")
      rule(short_code: "teamx", team_learning: true, category_override: "Ignored Category")

      names = described_class.filters.map(&:name)
      expect(names).to include("Team Based Learning")
      expect(names).not_to include("Seating")
      expect(names).not_to include("Ignored Category")

      entry = described_class.filters.find { |g| g.name == "Team Based Learning" }.entries.first
      expect(entry.short_code).to eq("teamx")
      expect(entry.label).to eq("TeamDesks")
    end

    it "excludes filterable: false characteristics" do
      characteristic(short_code: "hidden1", description: "Video: Blu-ray")
      rule(short_code: "hidden1", filterable: false)

      expect(described_class.filters.flat_map(&:entries).map(&:short_code)).not_to include("hidden1")
    end

    it "alphabetizes entries within a group by label, and groups alphabetically with Other pinned last" do
      characteristic(short_code: "z1", description: "Seating: Zeta")
      characteristic(short_code: "a1", description: "Seating: Alpha")
      characteristic(short_code: "m1", description: "Media: Screen")
      characteristic(short_code: "o1", description: "No colon at all")

      groups = described_class.filters

      expect(groups.map(&:name)).to eq(%w[Media Seating Other])

      seating = groups.find { |g| g.name == "Seating" }
      expect(seating.entries.map(&:label)).to eq(%w[Alpha Zeta])
    end
  end

  describe ".glossary" do
    it "includes filterable: false characteristics (unlike .filters)" do
      characteristic(short_code: "hidden1", description: "Video: Blu-ray", long_description: "Blu-ray disc player")
      rule(short_code: "hidden1", filterable: false)

      entry = described_class.glossary.flat_map(&:entries).find { |e| e.short_code == "hidden1" }

      expect(entry).not_to be_nil
      expect(entry.long_description).to eq("Blu-ray disc player")
    end

    it "still includes ordinary filterable characteristics" do
      characteristic(short_code: "seatmove", description: "Seating: Movable")

      expect(described_class.glossary.flat_map(&:entries).map(&:short_code)).to include("seatmove")
    end
  end

  describe ".label_for" do
    it "returns the human label for a known short_code" do
      characteristic(short_code: "seatmove", description: "Seating: Movable")

      expect(described_class.label_for("seatmove")).to eq("Movable")
    end

    it "falls back to the short_code itself (identity) for an unknown code" do
      expect(described_class.label_for("does-not-exist")).to eq("does-not-exist")
    end

    it "resolves labels even for filterable: false characteristics (glossary-backed, not filters-backed)" do
      characteristic(short_code: "hidden1", description: "Video: Blu-ray")
      rule(short_code: "hidden1", filterable: false)

      expect(described_class.label_for("hidden1")).to eq("Blu-ray")
    end
  end

  describe ".data_version" do
    it "changes when a RoomCharacteristic is created" do
      expect {
        characteristic(short_code: "newcode", description: "Seating: New")
      }.to change { described_class.data_version }
    end

    it "changes when a CharacteristicDisplayRule is created" do
      expect {
        rule(short_code: "newrule")
      }.to change { described_class.data_version }
    end

    # The create-based examples above always bump the `count` half of the
    # tuple, so they can't catch a regression that drops the max(updated_at)
    # term. These edit-based examples DON'T change any count — the only thing
    # that can move data_version is the updated_at timestamp. They FAIL if the
    # max(updated_at) terms are dropped from data_version, which is exactly the
    # D14 "admin edits an existing rule in place" invalidation path.
    it "changes when an existing CharacteristicDisplayRule is edited in place (updated_at, not count)" do
      existing = rule(short_code: "editrule")

      expect {
        existing.update!(icon_key: "different")
      }.to change { described_class.data_version }
        .and change { CharacteristicDisplayRule.count }.by(0) # edit, not create
    end

    it "changes when an existing RoomCharacteristic is edited in place (updated_at, not count)" do
      existing = characteristic(short_code: "editchar", description: "Seating: Old")

      expect {
        existing.update!(long_description: "reworded")
      }.to change { described_class.data_version }
        .and change { RoomCharacteristic.count }.by(0) # edit, not create
    end
  end

  describe "caching (Solid Cache, event-keyed per D14)" do
    # Test env defaults to :null_store (config/environments/test.rb); swap in
    # a real store so these examples can observe cache hits/misses.
    around do |example|
      original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
      Rails.cache = original_cache
    end

    it "serves repeated .filters calls from the cache without re-querying when data is unchanged" do
      characteristic(short_code: "seatmove", description: "Seating: Movable")

      expect(RoomCharacteristic).to receive(:select).once.and_call_original

      2.times { described_class.filters }
    end

    it "rebuilds (and re-queries) once the underlying data changes" do
      characteristic(short_code: "seatmove", description: "Seating: Movable")
      first = described_class.filters

      characteristic(short_code: "seatstat", description: "Seating: Stationary")
      second = described_class.filters

      expect(second).not_to eq(first)
      expect(second.flat_map(&:entries).map(&:short_code)).to include("seatmove", "seatstat")
    end
  end
end
