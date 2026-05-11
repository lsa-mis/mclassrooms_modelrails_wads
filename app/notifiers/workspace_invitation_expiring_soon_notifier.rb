# frozen_string_literal: true

class WorkspaceInvitationExpiringSoonNotifier < ApplicationNotifier
  category :account_access

  # Email is gated by the recipient's account_access.email preference (default: true).
  # before_enqueue throws :abort to skip the email job entirely when the recipient
  # opts out — saves an enqueued job we'd just discard. The DND case folds in here
  # too because account_access does not bypass DND.
  deliver_by :email do |config|
    config.mailer = "NotificationMailer"
    config.method = :workspace_invitation_expiring_soon
    # `== true` to abort on the :digest tri-state sentinel; see
    # WorkspaceMemberAddedNotifier for the full rationale.
    config.before_enqueue = -> { throw(:abort) unless recipient_pref(:email) == true }
    config.enqueue = true
  end

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_invitation_expiring_soon.message",
          locale: recipient_locale,
          workspace: event.record.resolved_workspace&.name,
          hours_remaining: event.record.expires_in_hours
        )
      end
    end

    def url
      Rails.application.routes.url_helpers.accept_invitation_path(token: event.record.token)
    end
  end

  private

  # Day-bucket idempotency override.
  #
  # The base ApplicationNotifier seeds (class, record.id, minute). This Notifier
  # is dispatched by `WorkspaceInvitationExpiringSweepJob`, which scans the
  # 24-hour expiring window every 6 hours. With a minute-bucket key, each
  # invitation in the window would receive ~4 dispatches per day (one per
  # sweep tick). A per-(invitation, day) key collapses those to one
  # notification per invitation per day until the invitation is accepted,
  # declined, or expired and falls out of the sweep window.
  #
  # Cross-day dispatches still succeed: an invitation that lingers in the
  # sweep window on day N and day N+1 will produce one notification each day,
  # which is the intended cadence (escalating reminder volume is digest
  # territory, not idempotency).
  def populate_idempotency_key
    return if idempotency_key.present?
    day = Time.current.to_date.iso8601
    self.idempotency_key = "#{self.class.name}_#{record.id}_#{day}"
  end
end
