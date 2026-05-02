class RenameUserPreferencesDigestIndex < ActiveRecord::Migration[8.1]
  # Rename to match project-wide convention: index_<table>_on_<columns>.
  # Original migration named it without the `_on_` infix; this aligns with
  # other indexes in the schema (index_users_on_email_address, etc).
  # Because SQLite's rename_index loses partial WHERE conditions, we drop and
  # recreate the index instead to preserve "WHERE digest_next_due_at IS NOT NULL".
  def up
    remove_index :user_preferences,
      name: "index_user_preferences_digest_next_due_at"
    add_index :user_preferences, :digest_next_due_at,
      where: "digest_next_due_at IS NOT NULL",
      name: "index_user_preferences_on_digest_next_due_at"
  end

  def down
    remove_index :user_preferences,
      name: "index_user_preferences_on_digest_next_due_at"
    add_index :user_preferences, :digest_next_due_at,
      where: "digest_next_due_at IS NOT NULL",
      name: "index_user_preferences_digest_next_due_at"
  end
end
