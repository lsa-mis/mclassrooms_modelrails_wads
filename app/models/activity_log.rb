class ActivityLog < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  # No FK on actor_id; the row keeps an encrypted name snapshot instead (#1122,
  # see /docs/developer/architecture, "An audit row outlives the people in it").
  encrypts :actor_name
  belongs_to :trackable, polymorphic: true
  belongs_to :workspace, optional: true

  # Persisted rows refuse instance-level update/destroy; relation-level bypasses are fenced
  # by spec/code_smells/activity_log_immutability_spec.rb, where the sweep has its carve-out.
  def readonly? = persisted?

  before_create :snapshot_actor_name

  enum :visibility, { workspace: "workspace", admin: "admin", personal: "personal" }, default: "workspace"

  # The audit retention floor's only membership test: the sweep job and record_security_event!
  # read this, never visibility (spec: activity_log_retention_sweep_job_spec).
  SECURITY_ACTIONS = %w[
    user.password_changed
    user.password_removed
    user.signed_in_new_device
    user.passkey_added
    user.passkey_removed
    user.suspended
    user.unsuspended
    user.unlocked
    operatorship.granted
    operatorship.revoked
  ].freeze

  # The members whose writer records the device os in metadata (Authenticatable's
  # new-device sign-in); the account activity card renders their _with_os label.
  SECURITY_ACTIONS_WITH_OS = %w[user.signed_in_new_device].freeze

  # The one writer of security-tier rows. A non-member action raises: a drifted literal would
  # otherwise write a plausible row the sweep deletes at 12 months, with the suite green.
  def self.record_security_event!(action:, user:, actor: user, visibility: "personal", metadata: {})
    unless SECURITY_ACTIONS.include?(action)
      raise ArgumentError, "#{action.inspect} is not in ActivityLog::SECURITY_ACTIONS"
    end

    create!(action: action, actor: actor, trackable: user,
            visibility: visibility, workspace_id: nil, metadata: metadata)
  end

  validates :action, presence: true

  scope :for_workspace, ->(workspace) { where(workspace: workspace) }
  scope :visible, -> { where(visibility: "workspace") }
  # Membership in SECURITY_ACTIONS is the test (#827); `personal` narrows out operator-actor
  # rows, which are written at admin visibility for the operations feed.
  scope :security_events_for, ->(user) {
    personal.where(action: SECURITY_ACTIONS, trackable: user).order(created_at: :desc)
  }
  scope :recent, -> { order(created_at: :desc).limit(20) }
  # Hidden even from an operator who is also the inviter (security.md invariant I3).
  INVITER_UNREADABLE_ACTIONS = %w[invitation.delivery_suppressed].freeze

  # Never personal rows: an operator reading a user's own security events is a fork's call.
  # `id` breaks created_at ties: bulk rows share a timestamp, and an OFFSET page must not repeat or skip one.
  scope :for_operations_feed, -> {
    where(visibility: %w[workspace admin])
      .where.not(action: INVITER_UNREADABLE_ACTIONS)
      .order(created_at: :desc, id: :desc)
  }
  # One entry per action family (activity_log_filters_spec), the fork's Curation::Apply families
  # included (building and floor come only from the legacy import). Re-EXPLAIN past ~5M rows (#1165).
  KINDS = %w[workspace membership invitation project resource user operatorship
             announcement characteristic_display_rule editor_assignment room
             sync_scope_rule unit_display_name building floor sync_run].freeze

  scope :of_kind, ->(kind) { where(arel_table[:action].matches("#{kind}.%")) }
  # Actor, User trackable, or a Membership of theirs; widening on purpose, since a rule-out
  # question must see the superset.
  scope :involving, ->(user) {
    where(actor_id: user.id)
      .or(where(trackable_type: "User", trackable_id: user.id))
      .or(where(trackable_type: "Membership", trackable_id: user.memberships.select(:id)))
  }
  # Every record the ledger search resolved, OR'd: a query naming a person and a workspace
  # means either, not both, and a rule-out must see the superset.
  scope :matching_any, ->(users:, workspaces:, projects:) {
    clauses = []
    if users.any?
      ids = users.map(&:id)
      clauses << where(actor_id: ids)
      clauses << where(trackable_type: "User", trackable_id: ids)
      clauses << where(trackable_type: "Membership", trackable_id: Membership.where(user_id: ids).select(:id))
    end
    clauses << where(workspace_id: workspaces.map(&:id)) if workspaces.any?
    clauses << where(trackable_type: "Project", trackable_id: projects.map(&:id)) if projects.any?
    clauses.reduce { |combined, clause| combined.or(clause) } || none
  }
  scope :within, ->(from, to) { where(created_at: from..to) }
  scope :oldest_first, -> { reorder(created_at: :asc, id: :asc) }
  # workspaces.name is the one plaintext name here (actor names are encrypted; operations.md);
  # instance-level rows have no name and sort last either way. Direction is checked, not interpolated.
  scope :by_workspace_name, ->(direction) {
    raise ArgumentError, "direction must be asc or desc" unless %w[asc desc].include?(direction.to_s)

    name = Arel.sql("LOWER(workspaces.name)")
    left_joins(:workspace).reorder((direction.to_s == "asc" ? name.asc : name.desc).nulls_last, created_at: :desc, id: :desc)
  }
  scope :at_instance_level, -> { where(workspace_id: nil) }

  # Returns an Array: trackable is polymorphic, so each type preloads on its own
  # slice (#1120).
  def self.for_feed
    # `all`: reached as relation.for_feed, where self is the class.
    logs = all.to_a
    preload_legacy_actors(logs)
    preload_trackables(logs, "Membership") do |members|
      ActiveRecord::Associations::Preloader.new(records: members, associations: :user).call
    end
    preload_trackables(logs, "User")
    logs
  end

  # Only pre-snapshot rows read the actor (#1122); the ops ledger preloads :actor itself for its
  # email pivot. Dead in a fresh fork; delete once no fork carries rows older than #1122.
  def self.preload_legacy_actors(logs)
    rows = logs.select { |log| log.pre_snapshot_actor? && !log.association(:actor).loaded? }
    return if rows.empty?

    ActiveRecord::Associations::Preloader.new(records: rows, associations: :actor).call
  end
  private_class_method :preload_legacy_actors

  def self.preload_trackables(logs, type)
    rows = logs.select { |log| log.trackable_type == type }
    return if rows.empty?

    ActiveRecord::Associations::Preloader.new(records: rows, associations: :trackable).call
    return unless block_given?

    # Read the association only for a caller that needs it: an unconditional read marks the
    # hop "used" to Bullet and would mask an unused eager load forever.
    trackables = rows.filter_map(&:trackable)
    yield trackables if trackables.any?
  end
  private_class_method :preload_trackables

  # One action, several sentences: the row's own metadata tells them apart (#932).
  def display_action
    case action
    when "membership.updated" then membership_display_action
    when "workspace.updated"  then workspace_display_action
    else action
    end
  end

  # The member the row is ABOUT, not its actor; an operatorship row's trackable is the User itself
  # (#1120). nil for other trackables and a hard-deleted membership; the partial supplies the noun.
  def display_member
    return trackable&.full_name if trackable_type == "User"

    tracked_membership&.user&.full_name
  end

  # Snapshot, else live actor (pre-#1122), else "a former member"; nil means a job did it.
  # membership.created names its member: onboarding creates it before any session.
  def display_subject
    return actor_name if actor_name.present?
    return actor&.full_name || I18n.t("activity.departed_actor") if pre_snapshot_actor?

    display_member if display_action == "membership.created"
  end

  def pre_snapshot_actor?
    actor_id.present? && actor_name.blank?
  end

  # Public because the ledger's details row reads it to name the member a
  # membership row is about (app/views/operations/activity_logs/_row.html.erb).
  def tracked_membership
    return nil unless trackable_type == "Membership"

    trackable
  end

  private

  def snapshot_actor_name
    self.actor_name = actor&.full_name
  end

  def membership_display_action
    transition = metadata.to_h.with_indifferent_access.dig(:changes, :discarded_at)
    return action if transition.blank?
    return "membership.reactivated" if transition.last.blank?

    self_removal? ? "membership.left" : "membership.deactivated"
  end

  def workspace_display_action
    transition = metadata.to_h.with_indifferent_access.dig(:changes, :suspended_at)
    return action if transition.blank?

    transition.last.blank? ? "workspace.unsuspended" : "workspace.suspended"
  end

  # The actor removed their own membership, so the row is a departure rather
  # than an eviction.
  def self_removal?
    member = tracked_membership
    member.present? && actor_id.present? && actor_id == member.user_id
  end
end
