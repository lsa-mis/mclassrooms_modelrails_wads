require "rails_helper"

RSpec.describe Archivable, type: :model do
  # Use Workspace as the host model (includes Archivable), mirroring discardable_spec
  let(:record) { create(:workspace) }

  describe "#archive!" do
    it "sets archived_at to current time" do
      freeze_time do
        record.archive!
        expect(record.archived_at).to eq(Time.current)
      end
    end
  end

  describe "#unarchive!" do
    it "clears archived_at" do
      record.archive!
      record.unarchive!
      expect(record.archived_at).to be_nil
    end
  end

  describe "scopes" do
    let!(:active_record) { create(:workspace) }
    let!(:archived_record) { create(:workspace).tap(&:archive!) }

    it "not_archived excludes archived" do
      expect(Workspace.not_archived).to include(active_record)
      expect(Workspace.not_archived).not_to include(archived_record)
    end

    it "archived includes only archived" do
      expect(Workspace.archived).to include(archived_record)
      expect(Workspace.archived).not_to include(active_record)
    end
  end
end
