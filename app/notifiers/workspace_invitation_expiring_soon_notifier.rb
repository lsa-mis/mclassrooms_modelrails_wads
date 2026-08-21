# frozen_string_literal: true

class WorkspaceInvitationExpiringSoonNotifier < ApplicationNotifier
  category :account_access
  severity :warning
  # Dispatched by WorkspaceInvitationExpiringSweepJob, which scans the
  # 24-hour expiring window every 6 hours. With the default minute bucket,
  # each invitation in the window would receive ~4 dispatches per day (one
  # per sweep tick); the day bucket collapses those to one per (invitation,
  # day). Cross-day dispatches still succeed — an invitation lingering in
  # the window notifies once per day, the intended cadence (escalating
  # reminder volume is digest territory, not idempotency).
  dedup_bucket :day

  # Email is gated by the recipient's account_access.email preference (default: true).
  # before_enqueue throws :abort to skip the email job entirely when the recipient
  # opts out — saves an enqueued job we'd just discard. The DND case folds in here
  # too because account_access does not bypass DND.
  deliver_by :email do |config|
    config.mailer = "NotificationMailer"
    config.method = :workspace_invitation_expiring_soon
    config.before_enqueue = -> { throw(:abort) unless deliver_email_now? }
    config.enqueue = true
  end

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_invitation_expiring_soon.message",
          locale: recipient_locale,
          workspace: event.record.resolved_workspace&.name,
          hours_remaining: event.record.expires_in_hours
        )
      end
    end

    def url
      Rails.application.routes.url_helpers.accept_invitation_path(token: event.record.token)
    end
  end
end
