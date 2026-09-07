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
#
# Exactly two ActivityLog write GUARANTEES exist — do not add a third. The
# tier is the contract, not the call site: several writers share this one.
#
#   BEST-EFFORT (rescues; never fails the operation it records) — this
#   concern, plus four writers that live outside it because their events
#   never reach these callbacks: Membership#record_ownership_demotion (a
#   callback-skipping CAS update_all), ApplicationController#log_blocked_role_grant
#   (a refusal, so there is no record to track),
#   Authenticatable#detect_and_record_new_device (a sign-in, corroborated by
#   the Session row), and Invitation#record_suppressed_delivery (fired from
#   mailer callbacks, where this concern's hooks must not run — the stamp it
#   records is written callback-free on purpose; PR 4 spec §7).
#
#   STRICT (no rescue; the audit row commits with the credential mutation or
#   neither does) — User#audit_password_digest_change and
#   WebauthnCredential#audit_added/#audit_removed.
#
# Tier and retention are independent axes: the new-device row is best-effort
# yet still an ActivityLog::SECURITY_ACTIONS member, so it keeps the security
# retention floor. Every SECURITY_ACTIONS row, either tier, is written through
# ActivityLog.record_security_event! — which owns that row shape.
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
    create_activity("#{model_name.param_key}.updated", tracked_update_metadata(changes))
  end

  # Overridable so a model can make a specific event human-readable or
  # admin-only. Defaults preserve existing behavior for every other model.
  def enrich_tracked_changes(changes)
    changes
  end

  # Overridable so a model can attach provenance an update row needs beyond the
  # changed columns — the create path has track_creation's metadata argument for
  # that, the update path had nothing. Same best-effort guarantee: this is
  # assembled inside create_activity's rescue, not a new writer.
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

  # The workspace an activity row is attributed to. Each includer answers for
  # itself (Membership returns its workspace, Invitation its
  # resolved_workspace); the default is the ambient request workspace for
  # models with no workspace of their own.
  def activity_workspace
    Current.workspace
  end
end
