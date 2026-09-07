# frozen_string_literal: true

# Fires when a Membership is created or a removed member is re-admitted. Dual
# recipients: the added user gets in-app + email; workspace owners (excluding
# the added user) get in-app only, with the digest pipeline as their intended
# email fallback.
# See /docs/developer/notifications (Notifier subclasses).
class WorkspaceMemberAddedNotifier < ApplicationNotifier
  category :workspace_activity
  severity :success
  record_preloads :user, :workspace

  recipients do
    added_user = record.user

    # Nobody is notified about their own action (the 37signals rule). The
    # actor rides as a PARAM, never off `record.granted_by`: that
    # attr_accessor is non-persisted, so an exclusion keyed on it would
    # exclude nobody the moment recipient resolution stopped reading the
    # in-memory record — silently, with no failing test.
    #
    # Owner resolution delegates to the canonical `Workspace#owners` helper;
    # `[added_user] + ...` plus `.uniq` handles the "added user is already an
    # owner" dedup case. `permitted_in_app` (ApplicationNotifier) preloads
    # :preferences and gates on the declared category's in_app preference.
    candidates = ([ added_user ] + record.workspace.owners).compact.uniq - [ params[:actor] ].compact
    permitted_in_app(candidates)
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
      throw(:abort) unless deliver_email_now?
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
      render_safe_or_placeholder do
        Rails.application.routes.url_helpers.workspace_path(present_or_gone!(event.record.workspace))
      end
    end
  end
end
