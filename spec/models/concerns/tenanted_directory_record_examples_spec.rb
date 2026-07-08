require "rails_helper"

# Temporary consumer for the "a tenanted directory record" shared example
# (spec/support/shared_examples/tenanted_directory_record.rb). Exercises it
# against a throwaway model, mirroring the tenanted_spec.rb pattern, until
# Task 2 introduces the first real domain model to include it.
class TenantedDirectoryTestRecord < ApplicationRecord
  include Tenanted
end

RSpec.describe TenantedDirectoryTestRecord, type: :model do
  before(:all) do
    ActiveRecord::Base.connection.create_table(:tenanted_directory_test_records, temporary: true, force: true) do |t|
      t.references :workspace
      t.timestamps
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table(:tenanted_directory_test_records, if_exists: true)
  end

  let(:record) { described_class.create!(workspace: create(:workspace)) }

  it_behaves_like "a tenanted directory record"
end
