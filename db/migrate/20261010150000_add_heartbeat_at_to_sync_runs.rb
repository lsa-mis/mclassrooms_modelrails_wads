class AddHeartbeatAtToSyncRuns < ActiveRecord::Migration[8.1]
  # A running sync renews this as it works; a run counts as stalled only once it goes quiet.
  def change
    add_column :sync_runs, :heartbeat_at, :datetime
  end
end
