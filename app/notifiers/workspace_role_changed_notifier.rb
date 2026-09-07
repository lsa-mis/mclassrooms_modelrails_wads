# frozen_string_literal: true

class WorkspaceRoleChangedNotifier < ApplicationNotifier
  category :account_access
  severity :info
  record_preloads :workspace, :role

  # Email is gated by the recipient's account_access.email preference (default: true).
  # before_enqueue throws :abort to skip the email job entirely when the recipient
  # opts out — saves an enqueued job we'd just discard. The DND case folds in here
  # too because account_access does not bypass DND.
  deliver_by :email do |config|
    config.mailer = "NotificationMailer"
    config.method = :workspace_role_changed
    config.before_enqueue = -> { throw(:abort) unless deliver_email_now? }
    config.enqueue = true
  end

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_role_changed.message",
          locale: recipient_locale,
          workspace: event.record.workspace.name,
          new_role: event.record.role.name
        )
      end
    end

    def url
      render_safe_or_placeholder do
        Rails.application.routes.url_helpers.workspace_path(present_or_gone!(event.record.workspace))
      end
    end
  end
end
