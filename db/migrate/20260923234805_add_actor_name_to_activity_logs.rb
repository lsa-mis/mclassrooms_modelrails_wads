class AddActorNameToActivityLogs < ActiveRecord::Migration[8.1]
  # A name snapshot replaces the actor_id FK (#1122); not backfilled. On SQLite this
  # rebuilds the table under the writer lock; rollback fails once an actor is deleted.
  def change
    add_column :activity_logs, :actor_name, :string

    remove_foreign_key :activity_logs, :users, column: :actor_id
  end
end
