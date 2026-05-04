# frozen_string_literal: true

class WorkspaceInvitationExpiringSoonNotifier < ApplicationNotifier
  category :account_access

  # Email is gated by the recipient's account_access.email preference (default: true).
  # before_enqueue throws :abort to skip the email job entirely when the recipient
  # opts out — saves an enqueued job we'd just discard. The DND case folds in here
  # too because account_access does not bypass DND.
  deliver_by :email do |config|
    config.mailer = "NotificationMailer"
    config.method = :workspace_invitation_expiring_soon
    config.before_enqueue = -> { throw(:abort) unless recipient_pref(:email) }
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
