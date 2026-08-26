class ReplaceActivityLogTrackableIndexWithCreatedAt < ActiveRecord::Migration[8.1]
  # Two index changes that are strictly dominating — cheaper INSERTs AND a
  # constant-time read (#823, measured on a synthetic 500k-row table):
  #
  #   * index_activity_logs_on_workspace_id is fully redundant with
  #     index_activity_logs_on_workspace_id_and_created_at — same leading
  #     column, so every query and the FK-enforcement path can use the
  #     composite as a prefix. It was pure write amplification: an extra
  #     B-tree insert on every ActivityLog.create!.
  #   * Appending created_at to the trackable index lets security_events_for
  #     sort on the index. Without it LIMIT does not bound the work: SQLite
  #     materializes every row for the user, builds a temp B-tree, sorts, then
  #     discards all but 10.
  #
  # 50k INSERTs: 79ms today, 71ms after (-10%). The settings-page read goes
  # from O(rows-per-user) to O(1). Pinned by the EXPLAIN assertion in
  # activity_log_spec.
  #
  # visibility is deliberately NOT in the index: every trackable_type='User'
  # row is personal (User does not include Trackable), so it has zero
  # selectivity and pure write cost.
  #
  # Deploy note: these are index operations, not the table rebuild that
  # add_check_constraint forces on SQLite — but CREATE INDEX still takes a
  # write lock for the length of the build, and migrations run at container
  # boot while the previous container serves traffic against the same file.
  # Check the production row count first on a large table.
  def change
    remove_index :activity_logs, :workspace_id, name: "index_activity_logs_on_workspace_id"

    remove_index :activity_logs, [ :trackable_type, :trackable_id ],
                 name: "index_activity_logs_on_trackable"

    add_index :activity_logs, [ :trackable_type, :trackable_id, :created_at ],
              name: "index_activity_logs_on_trackable_and_created_at"
  end
end
