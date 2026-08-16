# frozen_string_literal: true

# Fired by WorkspaceCapacitySweepJob when a workspace reaches >= 80% of its
# `max_members` quota; recipients are the workspace owners; category `:billing`
# (NOT security — DND suppresses these). Idempotency overrides the base
# minute bucket with a day bucket per (workspace, metric).
# See /docs/developer/notifications (Idempotency).
class WorkspaceCapacityApproachingNotifier < ApplicationNotifier
  category :billing
  severity :warning

  required_param :metric, :current, :limit

  recipients do
    workspace = record
    # Delegate owner resolution to the canonical helper on Workspace (which
    # joins :role, filters by slug "owner", and preloads :user to avoid N+1).
    # Filter the resulting Users by their billing.in_app preference: see the
    # class-level docs above for why this is the correct gate point. The
    # `preferences_for` helper wraps the schema-default JSONB blob for users
    # without a persisted UserPreferences row, so newly-created users are
    # correctly treated as opted-in for in-app at the column-default level.
    workspace.owners.select do |user|
      preferences_for(user).allow?(category: "billing", channel: "in_app")
    end
  end

  deliver_by :email do |config|
    config.mailer = "NotificationMailer"
    config.method = :workspace_capacity_approaching
    # `== true` aborts on the tri-state :digest sentinel.
    # See /docs/developer/notifications (Email gating and the `:digest` sentinel).
    config.before_enqueue = -> { throw(:abort) unless recipient_pref(:email) == true }
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

  private

  # Day-bucket idempotency, scoped per (workspace, metric) — see class-level
  # docs above for the full rationale.
  def populate_idempotency_key
    return if idempotency_key.present?
    day = Time.current.to_date.iso8601
    self.idempotency_key = "#{self.class.name}_#{record.id}_#{params[:metric]}_#{day}"
  end
end
