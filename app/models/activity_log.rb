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
    user.suspended
    user.unsuspended
    user.unlocked
    operatorship.granted
    operatorship.revoked
  ].freeze

  # The members whose writer records the device os in metadata (Authenticatable's
  # new-device sign-in); the account activity card renders their _with_os label.
  SECURITY_ACTIONS_WITH_OS = %w[user.signed_in_new_device].freeze

  # The one writer for security-tier rows (User password callbacks,
  # WebauthnCredential, Authenticatable, Operatorship all route here); the
  # row shape lives in exactly one place. `actor:` and `visibility:` default
  # to the self-event shape — the subject is the actor, personal visibility —
  # and a writer whose actor is someone else (an operator acting on a user)
  # overrides both, writing admin visibility so the row lands in the
  # operations feed rather than the subject's account card.
  #
  # A non-member action raises: a drifted literal ("user.passkey_add") would
  # otherwise write a plausible row the sweep deletes at 12 months instead of
  # the security floor, with the suite green. ArgumentError on purpose — a
  # programmer error propagates rather than being swallowed; callers choose
  # the write guarantee by rescuing or not.
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
  # The read side of the security tier. MEMBERSHIP is the test (#827): before
  # this, the card filtered on `personal` visibility alone, which describes who
  # a row is scoped to, not whether it is a security event.
  # `Trackable#activity_visibility` is an overridable seam — Membership already
  # returns "admin" through it — so a fork returning "personal" for a domain
  # event had its rows rendered under a security heading.
  # `visibility` is kept as a second, narrowing predicate rather than dropped:
  # the self-event default is personal, but an operator-actor row
  # (Operatorship's grant/revoke) is written at admin visibility on purpose,
  # so it belongs in the operations feed, not this card — this predicate is
  # what keeps it out.
  scope :security_events_for, ->(user) {
    where(action: SECURITY_ACTIONS, trackable: user, visibility: :personal)
      .order(created_at: :desc)
  }
  scope :recent, -> { order(created_at: :desc).limit(20) }
  # Invariant I3 (decline-and-block, defined in security.md "Invitation blocks"):
  # admin visibility alone doesn't keep a
  # suppressed-delivery row from an inviter here, since the operator IS often
  # the inviter. See operations.md "What the area does" (Activity).
  INVITER_UNREADABLE_ACTIONS = %w[invitation.delivery_suppressed].freeze

  # The operations feed: workspace and admin rows, never personal — an
  # operator reading a user's own security events is a privacy decision the
  # template leaves to a fork. id breaks the created_at tie: this is the app's
  # only OFFSET-paginated feed, and rows written in one burst (bulk_invite!)
  # share a timestamp, so without it a row can land on two pages or neither.
  scope :for_operations_feed, -> {
    where(visibility: %w[workspace admin])
      .where.not(action: INVITER_UNREADABLE_ACTIONS)
      .order(created_at: :desc, id: :desc)
  }
  # The operations ledger's Kind filter. One entry per action family the
  # locale tree sentences know (spec/models/activity_log_filters_spec.rb pins
  # the two lists together). Filters on the stored action prefix on purpose:
  # a trackable_type predicate seeks the trackable index and then sorts the
  # whole match in a temp B-tree, while a LIKE on action walks
  # index_activity_logs_on_created_at in output order and stops at LIMIT.
  # Under the 30-day default every Kind and Tier filter is a range seek on that
  # index; on All-time each is a full ordered walk of it, the same cost class as
  # the feed's COUNT. Re-EXPLAIN past ~5 M retained rows, where that crosses
  # 100 ms — an (action, created_at) or (visibility, created_at) index buys
  # nothing before then (#1165).
  # Fork: the families Curation::Apply writes join the template's list —
  # announcement, characteristic_display_rule, editor_assignment, room,
  # sync_scope_rule and unit_display_name, plus building and floor, which only
  # the legacy import writes; activity_log_filters_spec pins this list to the
  # activity.actions locale tree.
  KINDS = %w[workspace membership invitation project resource user operatorship
             announcement characteristic_display_rule editor_assignment room
             sync_scope_rule unit_display_name building floor].freeze

  scope :of_kind, ->(kind) { where(arel_table[:action].matches("#{kind}.%")) }
  # Rows the person acted in or was the subject of: actor, a User trackable
  # (operator actions on them), or a Membership of theirs. Widening on purpose —
  # a rule-out question must see the superset.
  scope :involving, ->(user) {
    where(actor_id: user.id)
      .or(where(trackable_type: "User", trackable_id: user.id))
      .or(where(trackable_type: "Membership", trackable_id: user.memberships.select(:id)))
  }
  # The ledger search's filter: every record `ActivityLog::Search` resolved,
  # OR'd into one predicate. Widening across the four kinds is the point — an
  # operator ruling something out must see the superset, and a query that
  # named a person and a workspace means either, not both.
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
  # The ledger's other SQL sort: workspaces.name is the one plaintext name in
  # the table (actor names are encrypted and cannot be ordered — see
  # operations.md, "What it deliberately does not do"). Instance-level rows
  # have no name and sit last in either direction, so "Instance" never reads
  # as a name that sorted first. Direction is checked, not interpolated.
  scope :by_workspace_name, ->(direction) {
    raise ArgumentError, "direction must be asc or desc" unless %w[asc desc].include?(direction.to_s)

    name = Arel.sql("LOWER(workspaces.name)")
    left_joins(:workspace).reorder((direction.to_s == "asc" ? name.asc : name.desc).nulls_last, created_at: :desc, id: :desc)
  }
  scope :at_instance_level, -> { where(workspace_id: nil) }

  # The feed's loader — call last in a chain
  # (`ActivityLog.for_workspace_feed(w, projects:).recent.for_feed`). Returns an
  # Array, not a Relation: `trackable` is polymorphic and only Membership
  # carries `user`, so a blanket `preload(trackable: :user)` raises
  # AssociationNotFoundError the moment a Project or Invitation row shares
  # the page — the membership hop, and separately an operatorship row's User
  # trackable, are preloaded on their own slice instead (#1120).
  def self.for_feed
    logs = includes(:actor).to_a
    preload_trackables(logs, "Membership") do |members|
      ActiveRecord::Associations::Preloader.new(records: members, associations: :user).call
    end
    preload_trackables(logs, "User")
    logs
  end

  def self.preload_trackables(logs, type)
    rows = logs.select { |log| log.trackable_type == type }
    return if rows.empty?

    ActiveRecord::Associations::Preloader.new(records: rows, associations: :trackable).call
    return unless block_given?

    # Reads the association only when a caller needs it — reading it
    # unconditionally would mark the hop "used" to Bullet regardless of
    # whether anything downstream did, permanently masking an unused eager
    # load. The Membership slice above stays invisible to Bullet the same
    # way, consumed only to feed the nested :user preload.
    trackables = rows.filter_map(&:trackable)
    yield trackables if trackables.any?
  end
  private_class_method :preload_trackables

  # The locale key the feed renders this row with — usually just `action`.
  # A deactivation, a self-removal and a reactivation all arrive as
  # `membership.updated` (Discardable#discard! is an ordinary update), so the
  # one action carries four different sentences and the feed used to call every
  # one of them a role change (#932). The row's own `changes` metadata tells
  # the status changes from the role change; the actor tells a removal from a
  # departure. A status change outranks a role change: `reactivate!` can carry
  # both, and losing or regaining access is the more consequential half.
  # A workspace lock/unlock is the same shape (Suspendable#suspend! is a
  # guarded update! too), splitting workspace.updated on suspended_at
  # instead of discarded_at.
  # Unknown shapes fall through to `action` itself. The partial has no
  # `default:` (the ModelRails/NoI18nDefault cop forbids it, #1022); in test
  # (`raise_on_missing_translations`) a missing activity.actions label raises,
  # while dev/prod render a "translation missing" marker instead.
  # spec/code_smells/dynamic_i18n_keys_have_values_spec.rb is what keeps a
  # missing label from shipping in the first place.
  def display_action
    case action
    when "membership.updated" then membership_display_action
    when "workspace.updated"  then workspace_display_action
    else action
    end
  end

  # The member a membership row is ABOUT, which is not its actor: Trackable
  # records the actor as whoever performed the change, so an owner removing
  # someone produced a row whose only name was the owner's. An operatorship
  # grant/revoke's trackable is a User directly, not a Membership —
  # Operatorship is above the workspace layer (#1120): without this case the
  # row read "granted a member operator access", naming neither party.
  # nil for every other trackable, and for a membership that has since been
  # hard-deleted — the partial supplies the neutral noun.
  def display_member
    return trackable&.full_name if trackable_type == "User"

    tracked_membership&.user&.full_name
  end

  # The row's sentence subject, or nil when the row genuinely does not know
  # one. membership.created is the only action whose subject is knowable
  # WITHOUT an actor: the row is about the person who joined. Onboarding
  # creates that membership in a User after_create, where Current.user cannot
  # exist yet — it delegates to a session that starts only after the signup
  # transaction commits. Every other action keeps the actor as subject; a nil
  # actor there means a job or console did it, and "System" is the truth.
  # Gated on the action for that reason: a bare actor-or-member fallback
  # renders a nil-actor deactivation as "Dee deactivated Dee".
  def display_subject
    return actor.full_name if actor

    display_member if display_action == "membership.created"
  end

  # Public because the ledger's details row reads it to name the member a
  # membership row is about (app/views/operations/activity_logs/_row.html.erb).
  def tracked_membership
    return nil unless trackable_type == "Membership"

    trackable
  end

  private

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
