# frozen_string_literal: true

require "rails_helper"
require_relative "../../db/migrate/20260903190000_enforce_one_preferences_row_per_user"

# The migration already ran for real; the before hook reverses it to reach the
# pre-migration state (a plain index), the example drives up/down from there,
# and RSpec's rollback undoes the DDL with everything else.
RSpec.describe EnforceOnePreferencesRowPerUser do
  let(:raw) { Class.new(ActiveRecord::Base) { self.table_name = "user_preferences" } }
  let(:migration) { described_class.new }
  let(:user) { create(:user) }

  before { ActiveRecord::Migration.suppress_messages { migration.down } }

  after do
    ActiveRecord::Base.connection.schema_cache.clear!
    UserPreferences.reset_column_information
  end

  it "keeps the most recently updated duplicate, then refuses a second row" do
    older = raw.create!(user_id: user.id, theme: "dark", created_at: 2.days.ago, updated_at: 2.days.ago)
    newer = raw.create!(user_id: user.id, theme: "light", created_at: 1.day.ago, updated_at: 1.hour.ago)

    ActiveRecord::Migration.suppress_messages { migration.up }

    expect(raw.where(user_id: user.id).pluck(:id)).to eq([ newer.id ])
    expect(raw.exists?(older.id)).to be(false)
    expect { raw.create!(user_id: user.id) }.to raise_error(ActiveRecord::RecordNotUnique)

    ActiveRecord::Migration.suppress_messages { migration.down }
    expect { raw.create!(user_id: user.id) }.not_to raise_error
  end
end
