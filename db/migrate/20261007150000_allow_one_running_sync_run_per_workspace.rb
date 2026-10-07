class AllowOneRunningSyncRunPerWorkspace < ActiveRecord::Migration[8.1]
  # Two overlapping syncs write the same rows; the index makes the second reservation fail instead.
  # Any extra running rows already present are older attempts, so they are failed first.
  def up
    execute <<~SQL
      UPDATE sync_runs SET status = 'failed', finished_at = COALESCE(finished_at, CURRENT_TIMESTAMP)
      WHERE status = 'running'
        AND id NOT IN (SELECT MAX(id) FROM sync_runs WHERE status = 'running' GROUP BY workspace_id)
    SQL
    add_index :sync_runs, :workspace_id, unique: true, where: "status = 'running'",
                                         name: "index_sync_runs_on_workspace_id_while_running"
  end

  def down
    remove_index :sync_runs, name: "index_sync_runs_on_workspace_id_while_running"
  end
end
