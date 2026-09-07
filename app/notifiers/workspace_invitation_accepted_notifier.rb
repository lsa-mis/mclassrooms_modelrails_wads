# frozen_string_literal: true

class WorkspaceInvitationAcceptedNotifier < ApplicationNotifier
  category :workspace_activity
  severity :success
  record_preloads :accepted_by, invitable: :workspace

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_invitation_accepted.message",
          locale: recipient_locale,
          accepter: event.record.accepted_by&.email_address,
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
