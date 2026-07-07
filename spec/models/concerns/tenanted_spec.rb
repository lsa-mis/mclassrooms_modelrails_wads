require "rails_helper"

# Tenanted's only including model (Project) was removed along with the
# template's example domain (see chore(fork): remove template example
# domain). Exercise the concern against a throwaway model backed by a
# temporary table so coverage doesn't depend on an app-specific model
# reappearing.
class TenantedTestRecord < ApplicationRecord
  include Tenanted
end

RSpec.describe Tenanted, type: :model do
  before(:all) do
    ActiveRecord::Base.connection.create_table(:tenanted_test_records, temporary: true, force: true) do |t|
      t.references :workspace
      t.timestamps
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table(:tenanted_test_records, if_exists: true)
  end

  describe "workspace association" do
    it "belongs to workspace" do
      expect(TenantedTestRecord.reflect_on_association(:workspace).macro).to eq(:belongs_to)
    end

    it "requires a workspace to be present" do
      record = TenantedTestRecord.new
      expect(record).not_to be_valid
      expect(record.errors[:workspace]).not_to be_empty
    end
  end

  describe ".for_current_workspace" do
    let(:workspace1) { create(:workspace) }
    let(:workspace2) { create(:workspace) }

    it "returns only records belonging to Current.workspace" do
      record1 = TenantedTestRecord.create!(workspace: workspace1)
      record2 = TenantedTestRecord.create!(workspace: workspace2)
      Current.workspace = workspace1

      expect(TenantedTestRecord.for_current_workspace).to include(record1)
      expect(TenantedTestRecord.for_current_workspace).not_to include(record2)
    end

    it "returns none when Current.workspace is nil" do
      TenantedTestRecord.create!(workspace: workspace1)
      Current.workspace = nil

      expect(TenantedTestRecord.for_current_workspace).to be_empty
    end
  end
end
