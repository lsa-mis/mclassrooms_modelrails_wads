class AddLastActiveAtToSessions < ActiveRecord::Migration[8.1]
  def up
    add_column :sessions, :last_active_at, :datetime

    # Backfill to *now*, not created_at: existing sessions are already trusted,
    # so give them a fresh idle window rather than retroactively expiring anyone
    # on deploy. The absolute-timeout clock still uses the real created_at.
    execute "UPDATE sessions SET last_active_at = CURRENT_TIMESTAMP WHERE last_active_at IS NULL"
  end

  def down
    remove_column :sessions, :last_active_at
  end
end
