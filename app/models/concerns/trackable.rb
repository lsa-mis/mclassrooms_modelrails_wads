# The best-effort tier of exactly two ActivityLog write guarantees; add no third. Reads Current by design.
# Writers per tier, retention and the Current deviation: /docs/developer/architecture (Activity Tracking).
module Trackable
  extend ActiveSupport::Concern

  # Storage filter first: metadata is plain JSON and the ledger renders it verbatim.
  # Declared by hand, since encrypted is not the same as secret (#1171).
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
    create_activity("#{model_name.param_key}.updated", tracked_update_metadata(changes))
  end

  # Overridable so a model can make a specific event human-readable or
  # admin-only. Defaults preserve existing behavior for every other model.
  def enrich_tracked_changes(changes)
    changes
  end

  # Overridable: provenance an update row needs beyond the changed columns. Built inside
  # create_activity's rescue, so it stays best-effort rather than becoming a new writer.
  def tracked_update_metadata(changes)
    { changes: enrich_tracked_changes(changes) }
  end

  def activity_visibility(_action)
    "workspace"
  end

  def create_activity(action, metadata = {})
    ActivityLog.create!(
      actor: Current.user,
      action: action,
      trackable: self,
      workspace: activity_workspace,
      visibility: activity_visibility(action),
      metadata: metadata
    )
  rescue StandardError => e
    Rails.logger.warn("Activity tracking failed for #{self.class.name}##{id} (#{action}): #{e.message}")
    Rails.error.report(e, handled: true, context: { trackable: "#{self.class.name}##{id}", action: action })
  end

  # An includer with a workspace of its own overrides this; the request's workspace is the
  # default only for models that have none.
  def activity_workspace
    Current.workspace
  end
end
