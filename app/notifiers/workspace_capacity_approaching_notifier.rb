# frozen_string_literal: true

# Fired by WorkspaceCapacitySweepJob when a workspace reaches >= 80% of its
# `max_members` quota; recipients are the workspace owners; category `:billing`
# (NOT security — DND suppresses these). Dedup is one notification per
# (workspace, metric, day) — the sweep re-fires within a day, the metric seed
# keeps members/projects alerts distinct.
# See /docs/developer/notifications (Idempotency).
class WorkspaceCapacityApproachingNotifier < ApplicationNotifier
  category :billing
  severity :warning
  dedup_bucket :day
  dedup_seed { params[:metric] }

  required_param :metric, :current, :limit

  recipients do
    # Owner resolution delegates to the canonical `Workspace#owners` helper;
    # `permitted_in_app` (ApplicationNotifier) preloads :preferences and gates
    # on the declared category's in_app preference — see the class-level docs
    # above for why the gate belongs here.
    permitted_in_app(record.owners)
  end

  deliver_by :email do |config|
    config.mailer = "NotificationMailer"
    config.method = :workspace_capacity_approaching
    config.before_enqueue = -> { throw(:abort) unless deliver_email_now? }
    config.enqueue = true
  end

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_capacity_approaching.message",
          locale: recipient_locale,
          workspace: event.record.name,
          metric: event.params[:metric],
          current: event.params[:current],
          limit: event.params[:limit]
        )
      end
    end

    def url
      Rails.application.routes.url_helpers.edit_workspace_settings_path(event.record)
    end
  end
end
