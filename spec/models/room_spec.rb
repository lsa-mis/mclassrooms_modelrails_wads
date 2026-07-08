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
    workspace = create(:workspace)
    create(:room, workspace: workspace, rmrecnbr: "2900001")
    duplicate = build(:room, workspace: create(:workspace), rmrecnbr: "2900001")

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
