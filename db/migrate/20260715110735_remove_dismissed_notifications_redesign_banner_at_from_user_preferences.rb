class RemoveDismissedNotificationsRedesignBannerAtFromUserPreferences < ActiveRecord::Migration[8.1]
  def change
    remove_column :user_preferences, :dismissed_notifications_redesign_banner_at, :datetime
  end
end
