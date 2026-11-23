require "rails_helper"

RSpec.describe Archivable, type: :model do
  # Workspace is the host model (includes Archivable)
  describe "#archive!" do
    it "sets archived_at to current time" do
      record = create(:workspace)

      freeze_time do
        record.archive!
        expect(record.archived_at).to eq(Time.current)
      end
    end
  end

  describe "#unarchive!" do
    it "clears archived_at" do
      record = create(:workspace)

      record.archive!
      record.unarchive!
      expect(record.archived_at).to be_nil
    end
  end

  describe "scopes" do
    it "not_archived excludes archived" do
      active_record = create(:workspace)
      archived_record = create(:workspace).tap(&:archive!)

      expect(Workspace.not_archived).to include(active_record)
      expect(Workspace.not_archived).not_to include(archived_record)
    end

    it "archived includes only archived" do
      active_record = create(:workspace)
      archived_record = create(:workspace).tap(&:archive!)

      expect(Workspace.archived).to include(archived_record)
      expect(Workspace.archived).not_to include(active_record)
    end
  end
end
