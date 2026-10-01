class DropRedundantNoticedNotificationIndexes < ActiveRecord::Migration[8.1]
  # Both are prefixes of index_noticed_notifications_on_recipient_read_created (#1199).
  def change
    remove_index :noticed_notifications, column: %i[recipient_type recipient_id],
                 name: "index_noticed_notifications_on_recipient"
    remove_index :noticed_notifications, column: %i[recipient_type recipient_id],
                 name: "index_noticed_notifications_unread", where: "read_at IS NULL"
  end
end
