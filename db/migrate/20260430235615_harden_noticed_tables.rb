class HardenNoticedTables < ActiveRecord::Migration[8.1]
  def change
    # Idempotency: dedicated column + partial unique index. Same Notifier class
    # targeting the same record with the same one-minute bucket dedupes at insert
    # time, atomically under SQLite BEGIN IMMEDIATE write serialization.
    add_column :noticed_events, :idempotency_key, :string

    add_index :noticed_events, :idempotency_key,
      unique: true,
      where: "idempotency_key IS NOT NULL",
      name: "index_noticed_events_on_idempotency_key"

    # Inline backfill for fork-data scenarios. dir.down is omitted: the column
    # drop in the auto-reversed `change` block cleans up the data automatically
    # (column gone → values gone), so no explicit data-undo step is needed.
    #
    # Inline backfill: if any existing noticed_events rows have an
    # idempotency_key in their params JSONB (from earlier work or forks
    # pulling this PR), populate the new column. No-op for fresh tables.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE noticed_events
          SET idempotency_key = json_extract(params, '$.idempotency_key')
          WHERE idempotency_key IS NULL
            AND json_extract(params, '$.idempotency_key') IS NOT NULL
        SQL
      end
      # No-op on down: column drop in reverse migration handles cleanup
    end

    # Hot path: unread-count queries scope on (recipient_type, recipient_id)
    # and filter where read_at IS NULL. Partial index keeps it tiny.
    add_index :noticed_notifications,
      [ :recipient_type, :recipient_id ],
      where: "read_at IS NULL",
      name: "index_noticed_notifications_unread"

    # Cascade FK so events deleted in tests/cleanup wipe their notifications.
    # Backstops gem-provided FK if it doesn't already cascade.
    add_foreign_key :noticed_notifications, :noticed_events,
      column: :event_id, on_delete: :cascade

    # seen_at always precedes read_at (notification can be emailed before read,
    # never read before being seen by any channel).
    add_check_constraint :noticed_notifications,
      "seen_at IS NULL OR read_at IS NULL OR read_at >= seen_at",
      name: "seen_before_read"

    # v1 commitment: User is the only valid recipient. Drop this when v1.x
    # broadens the polymorphic recipient.
    add_check_constraint :noticed_notifications,
      "recipient_type = 'User'",
      name: "recipient_type_user_only_v1"
  end
end
