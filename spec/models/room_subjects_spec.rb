require "rails_helper"

RSpec.describe "Room subject vocabulary" do
  # Insertion order IS the display rank, which is invisible and load-bearing:
  # reordering two lines silently reorders every gallery in production. Pin it.
  it "keeps the capture protocol's order" do
    expect(Room::SUBJECTS.keys).to eq(%i[front back podium rack inner_door other])
  end

  it "ranks by declaration order, unclassified last" do
    expect(Room.subject_rank("front")).to be < Room.subject_rank("rack")
    expect(Room.subject_rank(nil)).to be > Room.subject_rank("other")
  end

  it "suggests the protocol subject for a position" do
    expect(Room.suggested_subject_for(1)).to eq(:front)
    expect(Room.suggested_subject_for(4)).to eq(:rack)
    expect(Room.suggested_subject_for(6)).to eq(:other)
    expect(Room.suggested_subject_for(9)).to eq(:other)
    expect(Room.suggested_subject_for(0)).to be_nil
    expect(Room.suggested_subject_for(nil)).to be_nil
  end

  it "excludes retired subjects from what the editor offers, but keeps them valid" do
    allow(Room).to receive(:const_get).and_call_original
    stub_const("Room::SUBJECTS", Room::SUBJECTS.merge(
      inner_door: { key: "media.derived_alt.room.inner_door", retired: true }
    ))

    expect(Room.offerable_subjects).not_to include(:inner_door)
    expect(Room::SUBJECTS).to have_key(:inner_door)
    expect(Room.suggested_subject_for(5)).not_to eq(:inner_door)
  end
end
