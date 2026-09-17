# frozen_string_literal: true

# #927: the dispatch watermark. noticed commits the event + notification rows
# in one transaction and enqueues `Noticed::EventJob` after it; nothing records
# whether that enqueue ever landed. `dispatched_at` is stamped at the start of
# the job, and `NotificationDispatchReconcileJob` scans for rows that never got
# one. Nullable by construction — NULL *is* the "not yet dispatched" state.
#
# The index is partial and ordered by created_at because that is exactly the
# reconciler's scan (`dispatched_at IS NULL AND created_at BETWEEN ? AND ?`):
# once an event is stamped it leaves the index, so the index stays roughly
# empty in steady state rather than shadowing the whole ledger.
#
# The backfill is the load-bearing half. Every row written before this release
# is unstamped, older than the reconciler's grace window, and carries a
# non-zero `notifications_count` — nothing prunes events, and
# NotificationCleanupJob deletes notification rows without touching the
# counter. Adding the column without stamping them means the first production
# sweep re-enqueues the app's ENTIRE notification history: every email and
# every broadcast, again. Existing rows are stamped with their own created_at:
# a claim about when they were written, not a pretence that this migration
# delivered them.
#
# Raw SQL rather than an inline model: a datetime column copied onto a gem's
# table, no encryption and no app class in reach (see the frozen-migrations
# guard). `down` removes the index and the column, so the whole thing reverses.
class AddDispatchedAtToNoticedEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :noticed_events, :dispatched_at, :datetime
    execute "UPDATE noticed_events SET dispatched_at = created_at WHERE dispatched_at IS NULL"
    add_index :noticed_events, :created_at,
      where: "dispatched_at IS NULL",
      name: "index_noticed_events_undispatched"
  end

  def down
    remove_index :noticed_events, name: "index_noticed_events_undispatched"
    remove_column :noticed_events, :dispatched_at
  end
end
