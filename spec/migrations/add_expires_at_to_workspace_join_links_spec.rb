# frozen_string_literal: true

require "rails_helper"
require_relative "../../db/migrate/20260903143316_add_expires_at_to_workspace_join_links"

# The migration already ran for real (db:migrate, both environments — Task 2
# Step 3), so the schema this spec starts from already has `expires_at`. The
# `before` hook reverses it once to reach the pre-migration state the plan
# describes ("before up"), then the example drives up/down from there. SQLite
# DDL is transactional, so both reversals are undone by RSpec's per-example
# rollback along with everything else — the real, migrated schema is exactly
# what every other spec in the suite still sees.
RSpec.describe AddExpiresAtToWorkspaceJoinLinks do
  let(:raw_join_links) { Class.new(ActiveRecord::Base) { self.table_name = "workspace_join_links" } }
  let(:migration) { described_class.new }
  let(:workspace) { create(:workspace) }
  let(:user) { create(:user) }

  before { ActiveRecord::Migration.suppress_messages { migration.down } }

  # The per-example rollback restores the table, but not what the classes
  # remember about it: WorkspaceJoinLink and the connection's schema cache
  # saw the column-less table while this example ran, and a later spec in
  # the same process then read expires_at through that stale picture (an
  # Integer where a Time was expected, in the settings axe spec). Reset both.
  after do
    ActiveRecord::Base.connection.schema_cache.clear!
    WorkspaceJoinLink.reset_column_information
  end

  it "backfills a grace week for existing rows, then tightens the column to NOT NULL, and reverses" do
    link = raw_join_links.new(
      workspace_id: workspace.id, created_by_id: user.id,
      token_digest: "existing-digest", created_at: Time.current, updated_at: Time.current
    )
    link.save!

    travel_to Time.zone.parse("2026-09-03 12:00") do
      ActiveRecord::Migration.suppress_messages { migration.up }
      # Column cache: alone this example passed, but after any spec in the same
      # process had touched workspace_join_links it read expires_at as nil —
      # Active Record does not refresh a model's columns on DDL, and the
      # shadow class had loaded them from the pre-`up` table. Reproduced with
      # `rspec spec/models/workspace_join_link_spec.rb <this file> --order defined`.
      raw_join_links.reset_column_information

      expect(raw_join_links.find(link.id).expires_at).to eq(Time.current + 7.days)

      column = ActiveRecord::Base.connection.columns("workspace_join_links").find { _1.name == "expires_at" }
      expect(column.null).to be false

      ActiveRecord::Migration.suppress_messages { migration.down }

      expect(ActiveRecord::Base.connection.columns("workspace_join_links").map(&:name)).not_to include("expires_at")
    end
  end
end
