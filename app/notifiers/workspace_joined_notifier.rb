# frozen_string_literal: true

# Fires when someone admits themselves through an open join link. The single
# recipient is the joiner, and it exists because they are the actor: the
# 37signals rule drops them from WorkspaceMemberAddedNotifier, which would
# otherwise tell them in the third person that they joined. Same receipt shape
# as WorkspaceCreatedNotifier, including its copy rule: the message names no
# destination, because `url` is linked from the digest email only.
#
# No recipient param: on a self-join the actor is always `record.user`, so the
# recipient is read off the record rather than travelling alongside it.
#
# In-app only, no email leg (WelcomeNotifier's reasoning): they clicked join
# seconds ago and are being redirected into the workspace with a flash — an
# email restating it adds nothing. The invited-member welcome email stays where
# it is; that path orients someone about a workspace they were put into.
class WorkspaceJoinedNotifier < ApplicationNotifier
  category :workspace_activity
  severity :success
  record_preloads :workspace

  recipients do
    permitted_in_app([ record.user ].compact)
  end

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_joined.message",
          locale: recipient_locale,
          workspace: event.record.workspace.name
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
