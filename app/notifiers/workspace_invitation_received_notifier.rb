# frozen_string_literal: true

class WorkspaceInvitationReceivedNotifier < ApplicationNotifier
  category :account_access

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_invitation_received.message",
          locale: recipient_locale,
          workspace: event.record.invitable.name,
          inviter: event.record.invited_by&.email_address
        )
      end
    end

    def url
      Rails.application.routes.url_helpers.accept_invitation_path(
        token: event.record.token
      )
    end
  end
end
