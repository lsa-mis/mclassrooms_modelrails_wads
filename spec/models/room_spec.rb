require "rails_helper"

RSpec.describe Room, type: :model do
  let(:record) { create(:room) }
  it_behaves_like "a tenanted directory record"

  it "requires a unique rmrecnbr" do
    expect(build(:room, rmrecnbr: create(:room).rmrecnbr)).not_to be_valid
  end

  it "enforces rmrecnbr uniqueness globally, even across workspaces" do
    # Deliberate divergence from Campus/Unit: rmrecnbr is a U-M-wide natural
    # key (like Building's bldrecnbr), so uniqueness is NOT workspace-scoped.
    # Each room gets an explicit building so room + building share a tenant:
    # overriding :workspace alone leaves the factory's auto-built building in
    # a different workspace — a state impossible in production.
    original_building  = create(:building, workspace: create(:workspace))
    duplicate_building = create(:building, workspace: create(:workspace))
    create(:room, building: original_building, rmrecnbr: "2900001")
    duplicate = build(:room, building: duplicate_building, rmrecnbr: "2900001")

    expect(duplicate.workspace).not_to eq(original_building.workspace)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:rmrecnbr]).not_to be_empty
  end

  describe "associations" do
    it "requires a building" do
      expect(build(:room, building: nil, workspace: create(:workspace), building_name: "Modern Languages"))
        .not_to be_valid
    end

    it "does not require a floor, campus, or unit" do
      expect(build(:room, floor: nil, campus: nil, unit: nil)).to be_valid
    end
  end

  describe ".classroom (D8)" do
    it "includes only Classroom-typed rooms with a facility code and >1 seat" do
      classroom = create(:room)
      create(:room, room_type: "Class Laboratory")
      create(:room, facility_code: nil)
      create(:room, instructional_seat_count: 1)
      create(:room, instructional_seat_count: nil)
      expect(Room.classroom).to contain_exactly(classroom)
    end

    it "includes a room with exactly 2 seats (lower boundary)" do
      classroom = create(:room, instructional_seat_count: 2)
      expect(Room.classroom).to include(classroom)
    end

    it "includes a room with a blank (not nil) facility code" do
      # The rule is literally facility_code IS NOT NULL (D8) — a blank string
      # still passes; only NULL is excluded. Pinned so a future refactor to
      # `facility_code.blank?` semantics is a deliberate change, not a slip.
      classroom = create(:room, facility_code: "")
      expect(Room.classroom).to include(classroom)
    end
  end

  describe ".with_all_characteristics (D8)" do
    it "matches a room with all given short_codes but not a room with only one" do
      both = create(:room)
      create(:room_characteristic, room: both, short_code: "InstrComp")
      create(:room_characteristic, room: both, short_code: "LectureCap")

      one = create(:room)
      create(:room_characteristic, room: one, short_code: "InstrComp")

      expect(Room.with_all_characteristics(%w[InstrComp LectureCap])).to contain_exactly(both)
    end

    it "does not double-count when a room has two rows for the same short_code under different codes" do
      # Natural key is (room_id, code), not (room_id, short_code) — the feed
      # can legitimately produce two rows that share a short_code. Without
      # COUNT(DISTINCT short_code), the join would over-count rows and this
      # room would still match, but for the wrong reason; pinning the
      # DISTINCT so the count reflects distinct short_codes, not rows.
      room = create(:room)
      create(:room_characteristic, room: room, code: "201", short_code: "InstrComp")
      create(:room_characteristic, room: room, code: "205", short_code: "InstrComp")
      create(:room_characteristic, room: room, code: "301", short_code: "LectureCap")

      expect(Room.with_all_characteristics(%w[InstrComp LectureCap])).to contain_exactly(room)
    end

    it "does not inflate the required count when the query itself repeats a short_code" do
      room = create(:room)
      create(:room_characteristic, room: room, short_code: "InstrComp")
      create(:room_characteristic, room: room, short_code: "LectureCap")

      expect(Room.with_all_characteristics(%w[InstrComp InstrComp LectureCap])).to contain_exactly(room)
    end

    it "returns all rooms when given an empty array" do
      room = create(:room)
      expect(Room.with_all_characteristics([])).to contain_exactly(room)
    end

    it "composes with .classroom.listed" do
      matching = create(:room)
      create(:room_characteristic, room: matching, short_code: "InstrComp")
      create(:room_characteristic, room: matching, short_code: "LectureCap")

      non_classroom = create(:room, room_type: "Class Laboratory")
      create(:room_characteristic, room: non_classroom, short_code: "InstrComp")
      create(:room_characteristic, room: non_classroom, short_code: "LectureCap")

      partial = create(:room)
      create(:room_characteristic, room: partial, short_code: "InstrComp")

      expect(Room.classroom.listed.with_all_characteristics(%w[InstrComp LectureCap]))
        .to contain_exactly(matching)
    end
  end

  describe "visibility (D6)" do
    it "lists a room iff in_feed AND hidden_at IS NULL, composing with .classroom" do
      listed   = create(:room)
      hidden   = create(:room, :hidden)
      departed = create(:room, in_feed: false)
      expect(Room.listed).to contain_exactly(listed)
      expect(Room.hidden).to contain_exactly(hidden)
      expect(Room.not_in_feed).to contain_exactly(departed)
      expect(Room.classroom.listed).to contain_exactly(listed)  # Find-a-Room base
    end
  end

  describe "facility code normalization" do
    it "normalizes on save and resolves any casing/spacing" do
      room = create(:room, facility_code: "MLB 1200")
      expect(room.facility_code_normalized).to eq("mlb1200")
      expect(Room.find_by_facility_code("mlb-1200")).to eq(room)
      expect(Room.find_by_facility_code("nope999")).to be_nil
      expect(Room.find_by_facility_code(nil)).to be_nil
    end

    it "normalizes hyphenated, mixed-case codes like Aud-3" do
      room = create(:room, facility_code: "Aud-3")
      expect(room.facility_code_normalized).to eq("aud3")
      expect(Room.find_by_facility_code("AUD 3")).to eq(room)
    end
  end

  describe "#display_name" do
    it "is facility code, en-dash nickname when present, building+number fallback" do
      expect(build(:room, facility_code: "MLB1200", nickname: nil).display_name).to eq("MLB1200")
      expect(build(:room, facility_code: "MLB1200", nickname: "Aud 3").display_name).to eq("MLB1200 – Aud 3")
      expect(build(:room, facility_code: nil, nickname: nil, building_name: "Modern Languages",
                   room_number: "1200").display_name).to eq("Modern Languages 1200")
    end
  end

  describe ".search_name (D3 — FTS5)" do
    it "finds a room by facility code prefix, case-insensitively" do
      room = create(:room, facility_code: "MLB1200")
      expect(Room.search_name("mlb")).to contain_exactly(room)
      expect(Room.search_name("MLB")).to contain_exactly(room)
    end

    it "matches on nickname, room number, rmrecnbr, and building name" do
      room = create(:room, nickname: "Aud 3", room_number: "1200", rmrecnbr: "2900123",
                            building_name: "Mason Hall")
      expect(Room.search_name("aud")).to contain_exactly(room)
      expect(Room.search_name("1200")).to contain_exactly(room)
      expect(Room.search_name("2900123")).to contain_exactly(room)
      expect(Room.search_name("maso")).to contain_exactly(room)
    end

    it "re-indexes on update: a renamed nickname stops matching the old term" do
      room = create(:room, nickname: "Old Name")
      expect(Room.search_name("old")).to contain_exactly(room)
      room.update!(nickname: "New Name")
      expect(Room.search_name("old")).to be_empty
      expect(Room.search_name("new")).to contain_exactly(room)
    end

    it "drops a room from the index when it is destroyed" do
      room = create(:room, facility_code: "MLB1200")
      expect { room.destroy! }.to change(Room, :count).by(-1)
      expect(Room.search_name("mlb")).to be_empty
    end

    it "composes with other scopes, e.g. .classroom.listed" do
      matching = create(:room, facility_code: "MLB1200")
      create(:room, facility_code: "MLB1300", room_type: "Office")
      create(:room, :hidden, facility_code: "MLB1400")
      expect(Room.classroom.listed.search_name("mlb")).to contain_exactly(matching)
    end

    it "returns Room.none for a blank query" do
      create(:room, facility_code: "MLB1200")
      expect(Room.search_name("")).to be_empty
      expect(Room.search_name(nil)).to be_empty
      expect(Room.search_name("   ")).to be_empty
    end

    it "does not raise or inject FTS5 syntax on hostile input" do
      create(:room, facility_code: "MLB1200")
      expect { Room.search_name(%q("mlb OR *)) }.not_to raise_error
      expect { Room.search_name("mlb*") }.not_to raise_error
      expect { Room.search_name("mlb-1200") }.not_to raise_error
      expect { Room.search_name("café") }.not_to raise_error
      expect { Room.search_name(%q(" UNION SELECT * FROM users--)) }.not_to raise_error
      # Tokens are reduced to bare [[:alnum:]] runs before being re-quoted, so
      # stray quotes/asterisks/SQL keywords never reach FTS5 as live syntax —
      # "OR"/"*" here are inert literal search terms, not boolean operators,
      # so this does NOT behave like an unbounded wildcard match.
      expect(Room.search_name(%q("mlb OR *))).to be_empty
    end

    it "keeps the index untouched when the surrounding transaction rolls back" do
      ActiveRecord::Base.transaction(requires_new: true) do
        create(:room, facility_code: "MLB9797")
        raise ActiveRecord::Rollback
      end
      expect(Room.search_name("mlb9797")).to be_empty
    end

    it "does not bleed into Building's search index" do
      create(:room, facility_code: "MLB1200")
      expect(Building.search_name("mlb")).to be_empty
    end

    it "rebuilds the index from scratch via .rebuild_search_index!" do
      room = create(:room, facility_code: "MLB1200")
      Room.connection.execute("DELETE FROM room_search_index")
      expect(Room.search_name("mlb")).to be_empty
      Room.rebuild_search_index!
      expect(Room.search_name("mlb")).to contain_exactly(room)
    end
  end

  describe "attachments" do
    it "allows PDF for the seating chart but not the photo; caps size at 10MB" do
      room = build(:room)
      room.photo.attach(io: StringIO.new("%PDF-"), filename: "a.pdf", content_type: "application/pdf")
      expect(room).not_to be_valid
      room = build(:room)
      room.seating_chart.attach(io: StringIO.new("%PDF-"), filename: "c.pdf", content_type: "application/pdf")
      expect(room).to be_valid
    end
  end
end
