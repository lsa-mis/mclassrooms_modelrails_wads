class ActivityLog < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :trackable, polymorphic: true
  belongs_to :workspace, optional: true

  # The audit trail is best-effort to write (Trackable rescues rather than
  # failing the business operation — see /docs/developer/architecture) and immutable
  # after: persisted rows refuse instance-level update/destroy. Relation-level
  # bypasses (update_all/delete_all) are fenced by
  # spec/code_smells/activity_log_immutability_spec.rb, where the retention
  # sweep job (#438) has its explicit carve-out.
  def readonly? = persisted?

  enum :visibility, { workspace: "workspace", admin: "admin", personal: "personal" }, default: "workspace"

  # The security tier: the ONLY membership test for the audit retention floor.
  # ActivityLogRetentionSweepJob's exemption and record_security_event! below
  # reference this same constant — never re-derive the set from visibility,
  # which also carries non-security personal/admin rows.
  # Spec: activity_log_retention_sweep_job_spec.
  SECURITY_ACTIONS = %w[
    user.password_changed
    user.password_removed
    user.signed_in_new_device
    user.passkey_added
    user.passkey_removed
  ].freeze

  # The members whose writer records the device os in metadata (Authenticatable's
  # new-device sign-in); the account activity card renders their _with_os label.
  SECURITY_ACTIONS_WITH_OS = %w[user.signed_in_new_device].freeze

  # The one writer for security-tier rows (User password callbacks,
  # WebauthnCredential, Authenticatable all route here). Two reasons it exists:
  # the row shape lives in exactly one place, and an action outside
  # SECURITY_ACTIONS raises instead of writing. Without the guard a drifted
  # literal ("user.passkey_add") would still write a plausible-looking row that
  # the sweep deletes at 12 months instead of the security floor — audit
  # evidence lost silently, with the whole suite green.
  #
  # ArgumentError is deliberate: a non-member action is a programmer error, so
  # it propagates through Authenticatable's ActiveRecord-only rescue rather
  # than being swallowed. This method does not choose the write guarantee —
  # callers do, by rescuing or not.
  def self.record_security_event!(action:, user:, metadata: {})
    unless SECURITY_ACTIONS.include?(action)
      raise ArgumentError, "#{action.inspect} is not in ActivityLog::SECURITY_ACTIONS"
    end

    create!(action: action, actor: user, trackable: user,
            visibility: "personal", workspace_id: nil, metadata: metadata)
  end

  validates :action, presence: true

  scope :for_workspace, ->(workspace) { where(workspace: workspace) }
  scope :visible, -> { where(visibility: "workspace") }
  # The read side of the security tier. MEMBERSHIP is the test (#827): before
  # this, the card filtered on `personal` visibility alone, which describes who
  # a row is scoped to, not whether it is a security event.
  # `Trackable#activity_visibility` is an overridable seam — Membership already
  # returns "admin" through it — so a fork returning "personal" for a domain
  # event had its rows rendered under a security heading.
  # `visibility` is kept as a second, narrowing predicate rather than dropped:
  # record_security_event! always writes personal, so a security action at any
  # other visibility is malformed, and an existing spec deliberately pins that
  # such a row stays out of this card.
  scope :security_events_for, ->(user) {
    where(action: SECURITY_ACTIONS, trackable: user, visibility: :personal)
      .order(created_at: :desc)
  }
  scope :recent, -> { order(created_at: :desc).limit(20) }
  # The feed's loader — call it last in a chain
  # (`ActivityLog.visible.for_workspace(w).recent.for_feed`). It returns an
  # Array because the membership hop cannot be one `includes`: `trackable` is
  # polymorphic and Membership is the only tracked model carrying `user`, so a
  # blanket `preload(trackable: :user)` raises AssociationNotFoundError the
  # first time an Invitation row shares the page. Restricting the hop
  # to the membership slice also keeps the eager-load off pages that have no
  # membership rows, where Bullet would report it as unused.
  def self.for_feed
    logs = includes(:actor).to_a
    membership_rows = logs.select { |log| log.trackable_type == "Membership" }
    return logs if membership_rows.empty?

    ActiveRecord::Associations::Preloader.new(records: membership_rows, associations: :trackable).call
    members = membership_rows.filter_map(&:trackable)
    ActiveRecord::Associations::Preloader.new(records: members, associations: :user).call if members.any?
    logs
  end

  # The locale key the feed renders this row with — usually just `action`.
  # A deactivation, a self-removal and a reactivation all arrive as
  # `membership.updated` (Discardable#discard! is an ordinary update), so the
  # one action carries four different sentences and the feed used to call every
  # one of them a role change (#932). The row's own `changes` metadata tells
  # the status changes from the role change; the actor tells a removal from a
  # departure. A status change outranks a role change: `reactivate!` can carry
  # both, and losing or regaining access is the more consequential half.
  # Unknown shapes fall through to `action`, which the partial's `default:`
  # humanizes — true, if plain.
  def display_action
    return action unless action == "membership.updated"

    transition = metadata.to_h.with_indifferent_access.dig(:changes, :discarded_at)
    return action if transition.blank?
    return "membership.reactivated" if transition.last.blank?

    self_removal? ? "membership.left" : "membership.deactivated"
  end

  # The member a membership row is ABOUT, which is not its actor: Trackable
  # records the actor as whoever performed the change, so an owner removing
  # someone produced a row whose only name was the owner's. nil for every other
  # trackable, and for a membership that has since been hard-deleted — the
  # partial supplies the neutral noun.
  def display_member
    tracked_membership&.user&.full_name
  end

  private

  def tracked_membership
    return nil unless trackable_type == "Membership"

    trackable
  end

  # The actor removed their own membership, so the row is a departure rather
  # than an eviction.
  def self_removal?
    member = tracked_membership
    member.present? && actor_id.present? && actor_id == member.user_id
  end
end
