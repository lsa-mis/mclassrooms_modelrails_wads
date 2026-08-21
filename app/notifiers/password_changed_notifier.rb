# frozen_string_literal: true

class PasswordChangedNotifier < ApplicationNotifier
  category :security
  severity :danger

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t("notifications.password_changed.message",
               locale: recipient_locale,
               user_name: event.record.first_name)
      end
    end

    def url
      # Connected accounts is the closest security-adjacent landing: no logged-in
      # password-change route exists yet (passwords resource is forgot-password only).
      Rails.application.routes.url_helpers.settings_connected_accounts_path
    end
  end
end
