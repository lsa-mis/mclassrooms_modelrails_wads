# frozen_string_literal: true

# Fires when a Membership is created. Dual recipients: the added user gets
# in-app + email; workspace owners (excluding the added user) get in-app only,
# with the digest pipeline as their intended email fallback.
# See /docs/developer/notifications (Notifier subclasses).
class WorkspaceMemberAddedNotifier < ApplicationNotifier
  category :workspace_activity
  severity :success

  recipients do
    added_user = record.user
    workspace = record.workspace

    # Delegate owner resolution to the canonical helper on Workspace (which joins
    # :role, filters by slug "owner", and preloads :user to avoid N+1). Then
    # `[added_user] + ...` plus `.uniq` handles the "added user is already an
    # owner" dedup case without changing observable behavior.
    candidates = ([ added_user ] + workspace.owners).compact.uniq

    # Preload :preferences in one query — `preferences_for(user)` accesses
    # `user.preferences` per-user, which without preloading is N+1 when the
    # candidate set has more than one user. Surfaced by the Reshape 2a
    # open-link self-join request specs (Bullet caught it).
    ActiveRecord::Associations::Preloader.new(records: candidates, associations: :preferences).call

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
    # `== true` aborts on the tri-state :digest sentinel (else digest items fire as instant emails).
    # See /docs/developer/notifications (Email gating and the `:digest` sentinel).
    config.before_enqueue = lambda {
      throw(:abort) unless recipient_id == event.record.user_id
      throw(:abort) unless recipient_pref(:email) == true
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
