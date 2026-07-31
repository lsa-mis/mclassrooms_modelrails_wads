class UserPreferences < ApplicationRecord
  belongs_to :user

  enum :theme, { light: "light", dark: "dark", system: "system" }, default: "system"

  # Notifiers pass this straight to `I18n.t(locale:)`, which raises
  # I18n::InvalidLocale for anything outside the pinned available_locales
  # (see config/application.rb). Keep unsupported values out of the column.
  validates :locale,
            length: { maximum: 10 },
            inclusion: { in: ->(_) { I18n.available_locales.map(&:to_s) } },
            allow_nil: true
  validates :timezone, length: { maximum: 50 }, allow_nil: true
  validates :docs_mode, length: { maximum: 20 }, allow_nil: true

  def notification_preferences_object
    NotificationPreferences.new(notification_preferences, user: user)
  end
end
