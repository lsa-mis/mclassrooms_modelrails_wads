require "rails_helper"

RSpec.describe Setting, type: :model do
  describe "validations" do
    it "requires a key" do
      expect(build(:setting, key: nil)).not_to be_valid
    end

    it "rejects a duplicate key" do
      create(:setting, key: "dupe")
      expect { create(:setting, key: "dupe") }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe ".fetch / .put" do
    it "returns nil for a key that was never set" do
      expect(Setting.fetch("never_set")).to be_nil
    end

    it "stores and returns the value as a string" do
      Setting.put("widgets", 42)
      expect(Setting.fetch("widgets")).to eq("42")
    end

    it "updates the same row in place on a second write" do
      Setting.put("widgets", 1)
      expect { Setting.put("widgets", 2) }.not_to change(Setting, :count)
      expect(Setting.fetch("widgets")).to eq("2")
    end
  end

  describe ".capacity_filter_max" do
    it "returns the default when unset" do
      expect(Setting.capacity_filter_max).to eq(Setting::CAPACITY_FILTER_MAX_DEFAULT)
    end

    it "returns the stored value as an Integer after the writer is used" do
      Setting.capacity_filter_max = 120
      value = Setting.capacity_filter_max
      expect(value).to eq(120)
      expect(value).to be_an(Integer)
    end

    it "updates the same row in place on a second write" do
      Setting.capacity_filter_max = 120
      expect { Setting.capacity_filter_max = 130 }.not_to change(Setting, :count)
      expect(Setting.capacity_filter_max).to eq(130)
    end

    it "coerces a numeric string via Integer()" do
      Setting.capacity_filter_max = "175"
      expect(Setting.capacity_filter_max).to eq(175)
    end
  end

  describe ".recompute_capacity_filter_max! (D12)" do
    it "rounds the classroom seat max up to the nearest 25 (60 -> 75)" do
      create(:room, instructional_seat_count: 60)
      expect(Setting.recompute_capacity_filter_max!).to eq(75)
      expect(Setting.capacity_filter_max).to eq(75)
    end

    it "rounds the classroom seat max up to the nearest 25 (76 -> 100)" do
      create(:room, instructional_seat_count: 76)
      expect(Setting.recompute_capacity_filter_max!).to eq(100)
    end

    it "falls back to the default when there are zero classrooms" do
      expect(Room.classroom.count).to eq(0)
      expect(Setting.recompute_capacity_filter_max!).to eq(Setting::CAPACITY_FILTER_MAX_DEFAULT)
      expect(Setting.capacity_filter_max).to eq(Setting::CAPACITY_FILTER_MAX_DEFAULT)
    end

    it "ignores non-classroom rooms even with a much higher seat count" do
      create(:room, instructional_seat_count: 60)
      create(:room, room_type: "Class Laboratory", instructional_seat_count: 500)
      expect(Setting.recompute_capacity_filter_max!).to eq(75)
    end
  end
end
