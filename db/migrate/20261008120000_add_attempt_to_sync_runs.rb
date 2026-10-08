class AddAttemptToSyncRuns < ActiveRecord::Migration[8.1]
  # Each retry bumps it; a job carries the attempt it was queued for, so a superseded job cannot run the row.
  def change
    add_column :sync_runs, :attempt, :integer, null: false, default: 0
  end
end
