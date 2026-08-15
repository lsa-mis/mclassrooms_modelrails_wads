# frozen_string_literal: true

# Fires when a passkey is enrolled on an account. Enrollment mints a durable,
# phishing-resistant credential and revokes nothing, so it is the one gated
# action whose bypass would otherwise be silent — this notifier is the
# telemetry that makes that risk visible (2026-08-12 reauth-defaults panel).
# Mirrors PasswordChangedNotifier's shape: `category :security` bypasses DND,
# in-app channel gated by per-recipient preferences.
class PasskeyAddedNotifier < ApplicationNotifier
  category :security
  severity :danger

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t("notifications.passkey_added.message",
               locale: recipient_locale,
               user_name: event.record.first_name)
      end
    end

    def url
      Rails.application.routes.url_helpers.settings_passkeys_path
    end
  end
end
