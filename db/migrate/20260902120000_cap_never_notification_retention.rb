# frozen_string_literal: true

# PR 5 / D9: the "Never" retention choice is retired; users who had chosen it
# are capped at 365 days. Explicit JSON null was the only way "Never" was ever
# stored (NotificationPreferences#normalize_retention wrote nil for it), and
# json_type distinguishes that from an absent key, which the reader defaults.
#
# Best-effort backfill, not the invariant: NotificationPreferences#retention_days
# already answers 365 for an explicit null, so a row this misses (a rolling
# deploy's old container, a stale preferences page saved after the migration)
# still reads correctly. One statement; the table is small and SQLite holds
# the writer lock for its duration either way. No app constants here — this
# migration must replay on a fresh clone of any fork.
class CapNeverNotificationRetention < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE user_preferences
         SET notification_preferences = json_set(notification_preferences, '$.retention_days', 365)
       WHERE json_type(notification_preferences, '$.retention_days') = 'null'
    SQL
  end

  def down
    # Deliberate no-op: which users had chosen "Never" is not recoverable once
    # capped, and D9 rules out grandfathering machinery.
  end
end
