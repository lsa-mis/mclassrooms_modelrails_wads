require "rails_helper"

RSpec.describe AvailabilityBlock, type: :model do
  let(:record) { create(:availability_block) }

  it_behaves_like "a tenanted directory record"

  describe "schema (D11 — details-free structural guarantee)" do
    it "has no columns beyond the infrastructure needed to show busy/free state" do
      expect(AvailabilityBlock.column_names).to match_array(
        %w[id workspace_id room_id starts_at ends_at created_at updated_at]
      )
    end

    it "has no column that could carry event details" do
      expect(AvailabilityBlock.column_names).not_to include(
        a_string_matching(/title|course|instructor|description|name|subject|event/i)
      )
    end

    it "has a composite index on [room_id, starts_at]" do
      indexes = ActiveRecord::Base.connection.indexes("availability_blocks")
      index = indexes.find { |i| i.columns == [ "room_id", "starts_at" ] }
      expect(index).to be_present, "Expected composite index on (room_id, starts_at)"
    end
  end

  describe "validations" do
    it "requires starts_at" do
      block = build(:availability_block, starts_at: nil)
      expect(block).not_to be_valid
    end

    it "requires ends_at" do
      block = build(:availability_block, ends_at: nil)
      expect(block).not_to be_valid
    end

    it "is invalid when ends_at is before starts_at" do
      block = build(:availability_block, starts_at: 2.hours.from_now, ends_at: 1.hour.from_now)
      expect(block).not_to be_valid
      expect(block.errors[:ends_at]).not_to be_empty
    end

    it "is invalid when ends_at equals starts_at" do
      time = 1.hour.from_now
      block = build(:availability_block, starts_at: time, ends_at: time)
      expect(block).not_to be_valid
      expect(block.errors[:ends_at]).not_to be_empty
    end

    it "is valid when ends_at is after starts_at" do
      block = build(:availability_block, starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)
      expect(block).to be_valid
    end

    it "allows multiple blocks for the same room" do
      room = create(:room)
      create(:availability_block, room: room)
      other = build(:availability_block, room: room)

      expect(other).to be_valid
    end
  end
end
