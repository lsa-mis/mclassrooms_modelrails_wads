require "rails_helper"

RSpec.describe RoomCharacteristic, type: :model do
  let(:record) { create(:room_characteristic) }

  it_behaves_like "a tenanted directory record"

  describe "validations" do
    it "requires a code" do
      characteristic = build(:room_characteristic, code: nil)
      expect(characteristic).not_to be_valid
    end

    it "requires a short_code" do
      characteristic = build(:room_characteristic, short_code: nil)
      expect(characteristic).not_to be_valid
    end

    it "is invalid with a duplicate code within the same room" do
      room = create(:room)
      create(:room_characteristic, room: room, code: "101")
      duplicate = build(:room_characteristic, room: room, code: "101")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:code]).not_to be_empty
    end

    it "allows the same code on a different room" do
      create(:room_characteristic, code: "101")
      other = build(:room_characteristic, code: "101")

      expect(other).to be_valid
    end
  end
end
