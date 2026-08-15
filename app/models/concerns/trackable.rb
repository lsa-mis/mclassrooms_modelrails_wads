# Best-effort audit trail, by design: create_activity rescues and logs rather
# than ever failing the business write, and the after_commit placement means a
# crash between commit and callback loses the activity row, not the write.
# The Current.user/Current.workspace reads here are a deliberate deviation:
# the activity log is a cross-cutting concern where ambient request context
# beats threading an actor argument through every tracked write.
#
# Retention matches the guarantee: best-effort to write, immutable after
# (ActivityLog#readonly?), and BOUNDED — ActivityLogRetentionSweepJob deletes
# rows past 12 months (#438). If a fork promotes this trail to
# compliance-grade, the write moves inside the business transaction AND the
# retention window becomes a compliance decision, together.
module Trackable
  extend ActiveSupport::Concern

  SENSITIVE_ATTRIBUTES = %w[
    token password_digest password_reset_token
    oauth_token oauth_refresh_token
  ].freeze

  included do
    has_many :activities, as: :trackable, class_name: "ActivityLog"
    after_commit :track_creation, on: :create
    after_commit :track_update, on: :update
  end

  private

  def track_creation
    create_activity("#{model_name.param_key}.created")
  end

  def track_update
    changes = previous_changes.except("updated_at", "created_at")
    changes = changes.except(*SENSITIVE_ATTRIBUTES)
    return if changes.empty?
    create_activity("#{model_name.param_key}.updated", changes: enrich_tracked_changes(changes))
  end

  # Overridable so a model can make a specific event human-readable or
  # admin-only. Defaults preserve existing behavior for every other model.
  def enrich_tracked_changes(changes)
    changes
  end

  def activity_visibility(_action)
    "workspace"
  end

  def create_activity(action, metadata = {})
    ActivityLog.create!(
      actor: Current.user,
      action: action,
      trackable: self,
      workspace: resolve_workspace_for_activity,
      visibility: activity_visibility(action),
      metadata: metadata
    )
  rescue StandardError => e
    # Best-effort contract (see header): any tracking failure — validation,
    # statement, or otherwise — is logged and reported, never raised into the
    # business write that triggered it.
    Rails.logger.warn("Activity tracking failed for #{self.class.name}##{id} (#{action}): #{e.message}")
    Rails.error.report(e, handled: true, context: { trackable: "#{self.class.name}##{id}", action: action })
  end

  def resolve_workspace_for_activity
    respond_to?(:workspace) ? workspace : Current.workspace
  end
end
