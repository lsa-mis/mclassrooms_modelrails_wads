class AddNotificationPreferencesToUserPreferences < ActiveRecord::Migration[8.1]
  DEFAULT_PREFS = {
    "do_not_disturb" => false,
    "digest" => { "enabled" => true, "cadence" => "daily", "hour_local" => 8 },
    "categories" => {
      "security"           => { "in_app" => true,  "email" => true,  "digest" => false },
      "account_access"     => { "in_app" => true,  "email" => true,  "digest" => false },
      "workspace_activity" => { "in_app" => true,  "email" => false, "digest" => true  },
      "project_activity"   => { "in_app" => true,  "email" => false, "digest" => true  },
      "billing"            => { "in_app" => true,  "email" => true,  "digest" => false }
    },
    "retention_days" => 90
  }.freeze

  def change
    # SQLite has no native jsonb; :json maps to TEXT with JSON validation.
    # Spec uses "jsonb" for vocabulary; this migration uses :json (the dialect-correct type).
    add_column :user_preferences, :notification_preferences, :json,
      default: DEFAULT_PREFS, null: false
    add_column :user_preferences, :digest_next_due_at, :datetime
    add_column :user_preferences, :digest_last_sent_at, :datetime

    add_index :user_preferences, :digest_next_due_at,
      where: "digest_next_due_at IS NOT NULL",
      name: "index_user_preferences_digest_next_due_at"
  end
end
