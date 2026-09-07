# frozen_string_literal: true

# Confirms to the inviter (NOT the invitee) that they re-sent an invitation.
# The invitee email is delivered separately by InvitationMailer.invite from
# the resend controller action; this notifier is purely the in-app
# confirmation surface for the actor.
#
# The 1-minute idempotency bucket inherited from ApplicationNotifier is the
# UX guardrail against double-click resends — second click within the same
# minute returns :deduplicated, which the controller branches on to render
# a "recently sent" flash instead of a duplicate "sent" flash.
class WorkspaceInvitationResentNotifier < ApplicationNotifier
  category :account_access
  severity :info
  record_preloads invitable: :workspace

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_invitation_resent.message",
          locale: recipient_locale,
          invitee_email: event.record.email,
          workspace: event.record.resolved_workspace&.name
        )
      end
    end

    def url
      render_safe_or_placeholder do
        Rails.application.routes.url_helpers.workspace_members_path(
          present_or_gone!(event.record.resolved_workspace)
        )
      end
    end
  end
end
