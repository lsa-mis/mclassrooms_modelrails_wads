require "rails_helper"

RSpec.describe RoomSearch do
  include ClassroomBuilders

  let!(:mason)  { create(:building, name: "Mason Hall") }
  let!(:angell) { create(:building, name: "Angell Hall") }
  let!(:big)    { classroom(mason, "1200", 80, codes: %w[LectureCap InstrComp]) }
  let!(:small)  { classroom(mason, "2330", 20, codes: %w[LectureCap]) }
  let!(:aud)    { classroom(angell, "3000", 300, codes: %w[InstrComp]) }

  it "combines building, capacity and characteristic filters" do
    expect(described_class.new(building: "Mason", capacity_min: "40",
                               characteristics: %w[LectureCap]).results).to contain_exactly(big)
  end

  it "requires ALL selected characteristics (AND semantics)" do
    expect(described_class.new(characteristics: %w[LectureCap InstrComp]).results)
      .to contain_exactly(big) # small: LectureCap only; aud: InstrComp only
  end

  it "treats 0 and the capacity bound as unbounded and drops them from the summary" do
    allow(Setting).to receive(:capacity_filter_max).and_return(300)
    search = described_class.new(capacity_min: "0", capacity_max: "300")
    expect(search.results).to match_array([ big, small, aud ])
    expect(search.summary).to eq("")
  end

  it "matches normalized facility codes on the room-name filter" do
    expect(described_class.new(room: "mas1200").results).to contain_exactly(big)
  end

  it "sorts lettered floors before numeric (each natural), then room number naturally" do
    f_b, f_m, f2, f10 = %w[B M 2 10].map { |l| create(:floor, building: mason, label: l) }
    expected = [ [ "9", f_b ], [ "80", f_b ], [ "7", f_m ], [ "5", f2 ], [ "3", f10 ] ]
      .map { |num, fl| classroom(mason, num, 10, floor: fl) }
    expect(described_class.new({}).results.where(floor: [ f_b, f_m, f2, f10 ]).to_a).to eq(expected)
  end

  it "natural-sorts multi-character lettered floors within a prefix (B2 before B10), then the numeric bucket" do
    # Teeth: under a plain `floors.label COLLATE NOCASE` lettered tiebreak this
    # sorts B, B10, B2, M (alphabetical). The lettered bucket must split into
    # (alpha prefix, trailing digits as integer), all in SQL — not Ruby.
    floors = %w[B B2 B10 M 1 2 10].map { |l| create(:floor, building: mason, label: l) }
    floors.each { |fl| classroom(mason, "100", 10, floor: fl) }
    result = described_class.new({}).results.where(floor: floors).to_a
    expect(result.map(&:floor)).to eq(floors)
  end

  it "matches a nickname via case/whitespace-insensitive substring" do
    room = classroom(mason, "3005", 50)
    room.update!(nickname: "Grand Aud")
    expect(described_class.new(room: "grand aud").results).to contain_exactly(room)
  end

  describe "#per_page" do
    it "defaults to 30 when absent" do
      expect(described_class.new({}).per_page).to eq(30)
    end

    it "clamps an oversized value to the 100 max" do
      expect(described_class.new(per: "500").per_page).to eq(100)
    end

    it "falls back to the default for a non-positive value" do
      expect(described_class.new(per: "-1").per_page).to eq(30)
    end
  end

  it "filters by building name alone" do
    expect(described_class.new(building: "Angell").results).to contain_exactly(aud)
  end

  it "filters by unit_id alone" do
    unit_a = create(:unit, workspace: mason.workspace)
    unit_b = create(:unit, workspace: mason.workspace)
    big.update!(unit: unit_a)
    small.update!(unit: unit_b)
    expect(described_class.new(unit_id: unit_a.id).results).to contain_exactly(big)
  end

  it "returns all rooms in the base scope, sorted by default, when no filters are given" do
    expect(described_class.new({}).results).to contain_exactly(big, small, aud)
  end

  it "sorts by capacity ascending or descending when requested" do
    ids = [ big.id, small.id, aud.id ]
    expect(described_class.new(sort: "capacity_asc").results.where(id: ids).to_a).to eq([ small, big, aud ])
    expect(described_class.new(sort: "capacity_desc").results.where(id: ids).to_a).to eq([ aud, big, small ])
  end

  it "applies the sort in SQL (composes with LIMIT/OFFSET pagination), not a post-fetch Ruby sort" do
    sql = described_class.new({}).results.to_sql
    expect(sql).to match(/ORDER BY/i)
    expect(sql).to include("buildings")
  end

  it "produces a human-readable summary line combining multiple active filters" do
    allow(Setting).to receive(:capacity_filter_max).and_return(150)
    search = described_class.new(building: "Mason", capacity_min: "40", capacity_max: "100",
                                  characteristics: %w[LectureCap])
    expect(search.summary).to eq("Building: Mason, Capacity: 40-100, Filters: lecturecap")
  end

  describe ".unit_options" do
    it "returns distinct units present in listed classrooms, sorted by display name" do
      zeta  = create(:unit, workspace: mason.workspace, department_group: "ZZZ", description: "Zeta Unit")
      alpha = create(:unit, workspace: mason.workspace, department_group: "AAA", description: "Alpha Unit")
      big.update!(unit: zeta)
      small.update!(unit: alpha)
      expect(described_class.unit_options).to eq([ alpha, zeta ])
    end
  end
end
