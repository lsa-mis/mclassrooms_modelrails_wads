class AddCompositeIndexToNoticedNotificationsForReadStateQueries < ActiveRecord::Migration[8.1]
  # Panel review (Nate Berkopec): the existing recipient index does not
  # cover the read/unread + ordering pattern hit by:
  #
  #   - NotificationsHelper#recent_notifications_for_dropdown — splits
  #     into `where(read_at: nil).order(created_at: :desc)` AND
  #     `where.not(read_at: nil).order(created_at: :desc)`.
  #   - NotificationCleanupJob#cleanup_for — `where.not(read_at: nil)
  #     .where("read_at < ?", cutoff)`.
  #
  # The existing `index_noticed_notifications_unread` partial index
  # covers the `read_at IS NULL` half (and is the right tool for the
  # bell-button COUNT query). But the cleanup + dropdown's "recent read"
  # query falls back to a recipient-only scan + sort. Adding a composite
  # that includes read_at + created_at after the recipient pair lets
  # SQLite use index ordering for both filter AND sort.
  #
  # Lives alongside (not replacing) the existing partial index.
  def change
    add_index :noticed_notifications,
              [ :recipient_type, :recipient_id, :read_at, :created_at ],
              name: "index_noticed_notifications_on_recipient_read_created"
  end
end
