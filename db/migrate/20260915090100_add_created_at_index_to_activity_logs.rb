# frozen_string_literal: true

# The operations feed orders every workspace's rows by created_at. The only
# existing time index leads with workspace_id, so a global ORDER BY created_at
# cannot ride it. Plain (not partial): the feed spans all visibilities but
# personal, and filtering those out is cheap next to the sort.
class AddCreatedAtIndexToActivityLogs < ActiveRecord::Migration[8.1]
  def change
    add_index :activity_logs, :created_at
  end
end
