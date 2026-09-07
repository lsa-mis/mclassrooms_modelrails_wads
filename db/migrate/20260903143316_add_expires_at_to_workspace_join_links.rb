# frozen_string_literal: true

# #952: join links had no clock. SQLite cannot add a NOT NULL column without a
# default to a populated table, so: nullable, backfill, then tighten. Existing
# rows get a grace week from the migration run so nobody's shared link dies
# mid-sentence; the CHANGELOG says so.
class AddExpiresAtToWorkspaceJoinLinks < ActiveRecord::Migration[8.1]
  class RawJoinLink < ActiveRecord::Base
    self.table_name = "workspace_join_links"
  end

  def up
    add_column :workspace_join_links, :expires_at, :datetime
    RawJoinLink.where(expires_at: nil).update_all(expires_at: 7.days.from_now)
    change_column_null :workspace_join_links, :expires_at, false
  end

  def down
    remove_column :workspace_join_links, :expires_at
  end
end
