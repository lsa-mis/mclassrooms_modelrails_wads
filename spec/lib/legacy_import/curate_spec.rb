require "rails_helper"

RSpec.describe LegacyImport::Curate do
  let(:workspace) { create(:workspace, personal: false) }
  let!(:room) { create(:room, building: create(:building, workspace:), nickname: nil) }
  let!(:actor) { create(:user) }

  around { |example| Current.set(workspace:) { example.run } }

  it "writes the attributes and one audit row, returning nil" do
    error = nil
    expect {
      error = described_class.call(record: room, actor:, action: "room.legacy_imported", attributes: { nickname: "Aud 3" })
    }.to change(ActivityLog, :count).by(1)

    expect(error).to be_nil
    expect(room.reload.nickname).to eq("Aud 3")
    expect(ActivityLog.last).to have_attributes(action: "room.legacy_imported", actor:, trackable: room)
  end

  it "rolls back everything when the block raises, returning the message" do
    error = described_class.call(record: room, actor:, action: "room.legacy_imported", attributes: { nickname: "Aud 3" }) do
      raise ActiveStorage::IntegrityError, "bad bytes"
    end

    expect(error).to eq("ActiveStorage::IntegrityError: bad bytes")
    expect(room.reload.nickname).to be_nil
    expect(ActivityLog.where(trackable: room)).to be_empty
  end

  it "returns the validation message for an invalid record" do
    error = described_class.call(record: room, actor:, action: "room.legacy_imported", attributes: { rmrecnbr: nil })

    expect(error).to match(/rmrecnbr/i)
  end
end
