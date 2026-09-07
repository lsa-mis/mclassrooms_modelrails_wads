# frozen_string_literal: true

class WorkspaceInvitationDeclinedNotifier < ApplicationNotifier
  category :workspace_activity
  severity :info
  record_preloads invitable: :workspace

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_invitation_declined.message",
          locale: recipient_locale,
          decliner_email: event.record.email,
          workspace: event.record.resolved_workspace&.name
        )
      end
    end

    def url
      render_safe_or_placeholder do
        Rails.application.routes.url_helpers.workspace_path(present_or_gone!(event.record.resolved_workspace))
      end
    end
  end
end
