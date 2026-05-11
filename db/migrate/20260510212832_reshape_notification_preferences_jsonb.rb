class ReshapeNotificationPreferencesJsonb < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Add the banner-dismissal timestamp column and reshape every existing
  # user_preferences.notification_preferences JSONB to the new
  # parallel-list shape per the spec's backfill rules. Existing v1 5×3
  # matrix is collapsed via OR; digest=true in any cell promotes email
  # frequency to "daily"; legacy do_not_disturb flag becomes
  # quiet_hours.enabled.
  #
  # Rollback restores the schema column but cannot recover user-specific
  # legacy JSONB values — documented trade-off for an IA migration that
  # accepts the loss in exchange for not maintaining a dual-shape
  # backfill forever.
  # New-shape JSONB default for the column. Future inserts (via
  # create_preferences! or factories) start with this shape so callers
  # don't need to handle the old-shape-vs-new-shape duality.
  NEW_DEFAULT_JSONB = {
    "notification_types" => {
      "security" => true,
      "account_access" => true,
      "workspace_activity" => true,
      "project_activity" => true,
      "billing" => true
    },
    "delivery_methods" => {
      "in_app" => { "enabled" => true },
      "email"  => { "enabled" => true, "frequency" => "instant" }
    },
    "quiet_hours" => {
      "enabled" => false,
      "start" => "22:00",
      "end" => "07:00",
      "allow_urgent" => true
    },
    "retention_days" => 90
  }.freeze

  def up
    add_column :user_preferences, :dismissed_notifications_redesign_banner_at, :datetime

    # Update the column default to the new shape so future inserts
    # (factories, create_preferences!) start with the new structure.
    change_column_default :user_preferences, :notification_preferences, NEW_DEFAULT_JSONB

    UserPreferences.reset_column_information

    UserPreferences.unscoped.in_batches(of: 500) do |batch|
      batch.each do |prefs|
        reshaped = self.class.reshape_legacy_jsonb(prefs.notification_preferences)
        prefs.update_columns(notification_preferences: reshaped)
      end
    end
  end

  def down
    remove_column :user_preferences, :dismissed_notifications_redesign_banner_at
    # Restore schema-default JSONB for every row. User-specific values are
    # lost — documented trade-off (see migration header comment).
    default_jsonb = UserPreferences.column_defaults["notification_preferences"]
    UserPreferences.unscoped.update_all(notification_preferences: default_jsonb)
  end

  # Pure transformation. Tested via spec/migrations/* without touching
  # the database. Inputs: a v1 legacy JSONB hash (or nil). Output: the
  # new-shape JSONB hash.
  def self.reshape_legacy_jsonb(legacy)
    legacy = (legacy || {}).to_h
    categories = (legacy["categories"] || {}).to_h

    # Category-on rule: any cell true → category on. Security forced on
    # regardless of legacy (security floor — see spec decision #1).
    types = {
      "security"           => true,
      "account_access"     => any_channel_on?(categories["account_access"]),
      "workspace_activity" => any_channel_on?(categories["workspace_activity"]),
      "project_activity"   => any_channel_on?(categories["project_activity"]),
      "billing"            => any_channel_on?(categories["billing"])
    }

    # Channel-on rule: any category had this channel on → channel on.
    in_app_on = categories.any? { |_c, ch| ch.is_a?(Hash) && ch["in_app"] == true }
    email_on  = categories.any? { |_c, ch| ch.is_a?(Hash) && ch["email"]  == true }

    # When legacy has no categories at all (nil/empty), default both
    # channels on — matches the schema-default posture.
    if categories.empty?
      in_app_on = true
      email_on  = true
    end

    # Email frequency: any category had digest=true → daily; else instant.
    digest_was_on = categories.any? { |_c, ch| ch.is_a?(Hash) && ch["digest"] == true }

    {
      "notification_types" => types,
      "delivery_methods" => {
        "in_app" => { "enabled" => in_app_on },
        "email"  => { "enabled" => email_on, "frequency" => digest_was_on ? "daily" : "instant" }
      },
      "quiet_hours" => {
        "enabled"      => legacy["do_not_disturb"] == true,
        "start"        => "22:00",
        "end"          => "07:00",
        "allow_urgent" => true
      },
      "retention_days" => legacy.key?("retention_days") ? legacy["retention_days"] : 90
    }
  end

  def self.any_channel_on?(category_cell)
    return false unless category_cell.is_a?(Hash)
    category_cell["in_app"] == true || category_cell["email"] == true || category_cell["digest"] == true
  end
end
