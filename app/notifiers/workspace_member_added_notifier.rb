# frozen_string_literal: true

# Fires when a Membership is created — i.e. a user joins (or is added to) a workspace.
#
# Dual-recipient design (v1 catalog):
#   1. The added user — receives in-app + email (email gated by their workspace_activity.email pref).
#   2. All workspace owners EXCLUDING the added user — receive in-app only.
#      Email is suppressed per-recipient by an event-level conditional; the digest
#      pipeline (separate, scheduled job) is the intended fallback delivery for owners.
#
# In-app gating happens at recipient-resolution time: users whose workspace_activity.in_app
# preference is false are filtered out of `recipients` entirely, so no notification row is
# created for them. The :database delivery method is deprecated in Noticed 2.9.x — rows are
# auto-saved by the deliver pipeline — so per-recipient in-app gating MUST happen here.
#
# Users without a UserPreferences row (default factory output) are treated as "opted in" for
# in-app at the column default level via `ApplicationNotifier.preferences_for`, which wraps
# the schema default JSONB blob. Without this fallback, freshly-created users would be silently
# filtered out of every workspace_activity dispatch.
#
# Email gating mirrors the WorkspaceRoleChangedNotifier pattern: a `before_enqueue` lambda
# throws :abort to skip the email job when (a) the recipient is anyone other than the added
# user, or (b) the added user opted out of workspace_activity.email.
class WorkspaceMemberAddedNotifier < ApplicationNotifier
  category :workspace_activity

  recipients do
    added_user = record.user
    workspace = record.workspace

    # Owners include both global ("workspace_id IS NULL") and any workspace-scoped owner
    # role. The codebase currently seeds owner as a global role, but `effective_roles`
    # convention is to query both scopes for forward-compat with custom workspace roles.
    # `.includes(:user)` preloads the user association so the subsequent `.map(&:user)`
    # does not N+1 — the resolver runs synchronously in the request path that triggered
    # the membership create.
    owner_role_ids = Role.where(slug: "owner", workspace_id: [ nil, workspace.id ]).pluck(:id)
    owner_users = workspace.memberships.kept.where(role_id: owner_role_ids).includes(:user).map(&:user)

    candidates = ([ added_user ] + owner_users).compact.uniq

    # Filter out users whose workspace_activity.in_app preference is off (or DND).
    # See class-level docs above for why this is the correct gate point. The
    # `preferences_for` helper wraps the schema-default JSONB blob for users
    # without a persisted UserPreferences row.
    candidates.select do |user|
      preferences_for(user).allow?(category: "workspace_activity", channel: "in_app")
    end
  end

  # Email is gated to only the added user, AND only when their workspace_activity.email
  # pref is true. Owners get :digest (a separate scheduled pipeline) — never an immediate
  # email — which is enforced by the `recipient_id == event.record.user_id` clause.
  #
  # Compare on `*_id` (not on the loaded association) so Bullet doesn't flag an N+1 when
  # Noticed iterates `event.notifications.each` in the EventJob; recipient_id is a column
  # on the notification row and avoids the per-row association load that would trigger.
  deliver_by :email do |config|
    config.mailer = "NotificationMailer"
    config.method = :workspace_member_added
    config.before_enqueue = lambda {
      throw(:abort) unless recipient_id == event.record.user_id
      throw(:abort) unless recipient_pref(:email)
    }
    config.enqueue = true
  end

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_member_added.message",
          locale: recipient_locale,
          added_user_name: event.record.user.first_name,
          workspace: event.record.workspace.name
        )
      end
    end

    def url
      Rails.application.routes.url_helpers.workspace_path(event.record.workspace)
    end
  end
end
