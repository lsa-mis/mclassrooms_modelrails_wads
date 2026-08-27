class DropSeenAtFromNoticedNotifications < ActiveRecord::Migration[8.1]
  # `seen_at` was written by exactly one caller — the digest job, to itself —
  # and read by exactly one query, that same job's scope. It never described
  # anything a user did: `mark_seen!` had no production call site. So the
  # digest was deduping against its own bookkeeping rather than against
  # attention, and a notification read in-app was still emailed.
  #
  # Read state (`read_at`) is now the only per-row attention state. The
  # `seen_before_read` CHECK goes with the column it constrained.
  #
  # Deploy note: dropping a column and removing a CHECK are both table
  # rebuilds on SQLite (CREATE / INSERT … SELECT / DROP / RENAME), run inside
  # db:prepare at boot. Deploys are stop-then-start (max-replicas: 1), so this
  # lands in the outage window rather than contending with a live container —
  # see /docs/developer/deployment for the row-count guidance.
  def change
    remove_check_constraint :noticed_notifications,
                            "seen_at IS NULL OR read_at IS NULL OR read_at >= seen_at",
                            name: "seen_before_read"

    remove_column :noticed_notifications, :seen_at, :datetime, precision: nil
  end
end
