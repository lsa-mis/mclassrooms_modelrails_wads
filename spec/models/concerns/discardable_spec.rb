require "rails_helper"

RSpec.describe Discardable, type: :model do
  # Workspace is the host model (includes Discardable)
  describe "#discard!" do
    it "sets discarded_at to current time" do
      record = create(:workspace)

      freeze_time do
        record.discard!
        expect(record.discarded_at).to eq(Time.current)
      end
    end
  end

  describe "#undiscard!" do
    it "clears discarded_at" do
      record = create(:workspace)

      record.discard!
      record.undiscard!
      expect(record.discarded_at).to be_nil
    end
  end

  describe "scopes" do
    it "kept excludes discarded" do
      kept_record = create(:workspace)
      discarded_record = create(:workspace).tap(&:discard!)

      expect(Workspace.kept).to include(kept_record)
      expect(Workspace.kept).not_to include(discarded_record)
    end

    it "discarded includes only discarded" do
      kept_record = create(:workspace)
      discarded_record = create(:workspace).tap(&:discard!)

      expect(Workspace.discarded).to include(discarded_record)
      expect(Workspace.discarded).not_to include(kept_record)
    end
  end
end
