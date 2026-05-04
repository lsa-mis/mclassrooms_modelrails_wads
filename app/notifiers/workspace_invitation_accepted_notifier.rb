# frozen_string_literal: true

class WorkspaceInvitationAcceptedNotifier < ApplicationNotifier
  category :workspace_activity

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
      Rails.application.routes.url_helpers.workspace_path(event.record.resolved_workspace)
    end
  end
end
