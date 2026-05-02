# frozen_string_literal: true

class PasswordChangedNotifier < ApplicationNotifier
  category :security

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t("notifications.password_changed.message",
               locale: recipient_locale,
               user_name: event.record.first_name)
      end
    end

    def url
      # TODO(PR-3): point at a dedicated security hub when one ships. v1 has no
      # logged-in password-change route (the project's password resource is
      # `:new, :create` only, i.e. forgot-password flow). Connected accounts is
      # the closest available security-adjacent landing for now.
      Rails.application.routes.url_helpers.account_connected_accounts_path
    end
  end
end
