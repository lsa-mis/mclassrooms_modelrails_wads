# frozen_string_literal: true

class PasswordChangedNotifier < ApplicationNotifier
  category :security
  severity :danger
  # Without this, the base (class, record.id, minute) key collapses a change
  # and a removal for the same user inside one minute onto the SAME
  # idempotency key — the second #deliver hits RecordNotUnique and the more
  # consequential removal alert is silently dropped. Folding `removed` into
  # the seed makes the two copy branches independently dedupable, matching
  # the audit trail's per-branch ActivityLog row.
  dedup_seed { params[:removed] }

  notification_methods do
    def message
      render_safe_or_placeholder do
        if event.params[:removed]
          I18n.t("notifications.password_removed.message",
                 locale: recipient_locale,
                 user_name: event.record.first_name)
        else
          I18n.t("notifications.password_changed.message",
                 locale: recipient_locale,
                 user_name: event.record.first_name)
        end
      end
    end

    def url
      # Connected accounts is the closest security-adjacent landing: no logged-in
      # password-change route exists yet (passwords resource is forgot-password only).
      Rails.application.routes.url_helpers.settings_connected_accounts_path
    end
  end
end
