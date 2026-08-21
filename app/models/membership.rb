class Membership < ApplicationRecord
  # Raised by the last-owner invariants (validate_not_last_owner!,
  # enforce_owner_invariant!, enforce_owner_floor!) so controllers rescue the
  # NAMED condition instead of blanket-mapping every RecordInvalid to the
  # last-owner flash. Subclasses RecordInvalid so generic boundary rescues
  # keep working.
  class LastOwner < ActiveRecord::RecordInvalid; end

  include Discardable
  include Trackable
  include Broadcastable

  belongs_to :user
  belongs_to :workspace

  # Non-persisted grant provenance for the creation audit entry (G): set by
  # Workspace#admit when an invitation acceptance created this membership.
  attr_accessor :granted_by
  belongs_to :role

  validates :user_id, uniqueness: { scope: :workspace_id }
  validate :workspace_has_member_capacity, on: :create

  # Capacity race-safety net: the pre-flight validator's workspace.lock! is
  # silently a no-op across SQLite connections, so this post-INSERT COUNT is the
  # real guard — over-capacity → raise → roll back.
  # See /docs/developer/architecture (Concurrency).
  after_create :enforce_capacity_invariant

  # Notify the affected user whenever their role within the workspace changes.
  # Uses saved_change_to_role_id? rather than role_id_previously_changed? so it
  # also fires correctly under nested transactions where dirty tracking can lag.
  after_update_commit :notify_role_changed, if: :saved_change_to_role_id?

  # Notify the new member + workspace owners whenever a fresh membership is created.
  # `deliver(nil)` defers recipient resolution to the Notifier's `recipients` block.
  #
  # Gated by `workspace_has_other_owners?` — a workspace without owners *other
  # than this membership* (e.g. User#create_personal_workspace seeding the very
  # first owner-membership) has nobody for whom the "new member joined" event
  # is actionable; firing there would produce a self-notification at best.
  after_create_commit :notify_member_added, if: :workspace_has_other_owners?

  scope :search, ->(query) {
    return all if query.blank?
    sanitized = sanitize_sql_like(query.downcase)
    joins(:user).where(
      "LOWER(users.first_name) LIKE :q ESCAPE '\\' OR LOWER(users.last_name) LIKE :q ESCAPE '\\' OR LOWER(users.email_address) LIKE :q ESCAPE '\\'",
      q: "%#{sanitized}%"
    )
  }

  scope :filter_by_role, ->(role_slug) {
    return all if role_slug.blank?
    joins(:role).where(roles: { slug: role_slug })
  }

  scope :filter_by_status, ->(status) {
    case status
    when "active" then kept
    when "deactivated" then discarded
    else all
    end
  }

  scope :sorted_by, ->(column, direction) {
    dir = direction&.downcase == "asc" ? :asc : :desc
    case column
    when "name" then joins(:user).order(Arel.sql("users.first_name #{dir}, users.last_name #{dir}"))
    when "email" then joins(:user).order(Arel.sql("users.email_address #{dir}"))
    when "role" then joins(:role).order(Arel.sql("roles.name #{dir}"))
    else order(created_at: :desc)
    end
  }

  # Composed scope used by Workspaces::MembersController#index. Memberships
  # are excluded entirely when the status filter is "pending" — that filter
  # value selects pending invitations only, which live on Invitation.
  scope :for_members_index, ->(q:, role:, status:, sort:, direction:) {
    return none if status == "pending"

    includes(:user, :role)
      .search(q)
      .filter_by_role(role)
      .filter_by_status(status)
      .sorted_by(sort, direction)
  }

  # Kept owner-role memberships in the workspace, excluding the given
  # membership id — "are there OTHER owners besides this one?".
  def self.other_kept_owners(workspace_id, excluding:)
    kept.joins(:role)
        .where(workspace_id: workspace_id, roles: { slug: "owner" })
        .where.not(id: excluding)
  end

  # Role identity only — deliberately silent on kept/discarded state; the
  # owner-floor queries carry their own kept filtering.
  def owner?
    role.present? && role.owner?
  end

  def change_role!(new_role)
    demoting_owner = owner? && !new_role.owner?
    transaction do
      workspace.lock!
      update!(role: new_role)
      enforce_owner_floor! if demoting_owner
    end
  end

  def deactivate!
    transaction do
      workspace.lock!
      validate_not_last_owner!
      discard!
      enforce_owner_invariant!
    end
  end

  # Restoring a deactivated EXISTING member. Intentionally NOT guarded by
  # Workspace#admittable? — unlike outsider admission (Workspace#admit), which
  # blocks archived/locked/deleted. This path is only reachable through
  # WorkspaceScoped, which already gates deleted (.kept) and locked (the
  # suspended redirect), so only `archived` can reach here — and reactivating an
  # existing member of an archived workspace is intentionally allowed: archived
  # stays accessible to existing members, and the admin doing this is actively
  # in the workspace. The pinning test in membership_spec locks this in.
  def reactivate!
    undiscard!
  end

  def transfer_ownership_to!(target_membership)
    owner_role = Role.system_default!("owner")
    admin_role = Role.system_default!("admin")

    transaction do
      workspace.lock!

      # Atomic conditional demote: only succeeds if we're still the owner at
      # the moment of the UPDATE. The database serializes us against any
      # racing transfer; a racer that already demoted us produces 0 affected
      # rows here, and we abort *before* promoting target — preventing the
      # workspace from ending up with two owners. update_all skips
      # after_update_commit on self intentionally; the user initiating the
      # transfer doesn't need a self-targeted "your role changed" notice.
      rows = Membership.where(id: id)
                       .where(role_id: Role.where(slug: "owner").select(:id))
                       .update_all(role_id: admin_role.id)
      raise ActiveRecord::RecordInvalid, self if rows.zero?
      reload
      record_ownership_demotion(admin_role)

      target_membership.reload
      target_membership.update!(role: owner_role)
    end
  end

  private

  def broadcast_target
    workspace
  end

  def activity_workspace
    workspace
  end

  def workspace_has_member_capacity
    return unless workspace
    workspace.lock!
    if workspace.at_capacity?
      errors.add(:base, :workspace_member_limit)
    end
  end

  def enforce_capacity_invariant
    return unless workspace_id
    count = Membership.where(workspace_id: workspace_id, discarded_at: nil).count
    limit = Workspace.where(id: workspace_id).pick(:max_members)
    return unless limit && count > limit
    errors.add(:base, :workspace_member_limit)
    raise ActiveRecord::RecordInvalid, self
  end

  def validate_not_last_owner!
    if owner? && !Membership.other_kept_owners(workspace_id, excluding: id).exists?
      errors.add(:base, :last_owner)
      raise LastOwner, self
    end
  end

  # Race-safety net for validate_not_last_owner!: post-discard COUNT in the same
  # transaction; zero kept owners → raise to roll back. Non-owner discards skip.
  # See /docs/developer/architecture (Concurrency).
  def enforce_owner_invariant!
    return unless owner?
    # Self is already discarded here, so "any kept owner" == "any OTHER kept
    # owner" — the shared query reads identically either way.
    return if Membership.other_kept_owners(workspace_id, excluding: id).exists?
    errors.add(:base, :last_owner)
    raise LastOwner, self
  end

  # Owner-floor net for change_role! demotions: post-UPDATE EXISTS counts only
  # the OTHER owners (self is already demoted); zero left → roll back.
  # See /docs/developer/architecture (Concurrency).
  def enforce_owner_floor!
    # Self is already demoted here, so counting all kept owners == counting
    # the OTHER kept owners — the shared query reads identically either way.
    return if Membership.other_kept_owners(workspace_id, excluding: id).exists?
    errors.add(:base, :last_owner)
    raise LastOwner, self
  end

  # G (SEC-1 follow-up): membership.created previously carried EMPTY metadata,
  # and the invitation flow named only the accepting invitee — the most common
  # grant path recorded no role and no granter. The actor stays the invitee
  # (they performed the accept); the role and granter ride as metadata.
  def track_creation
    metadata = { "role" => role&.slug }
    metadata["granted_by"] = granted_by.id if granted_by
    create_activity("membership.created", metadata.compact)
  end

  # G (SEC-1 follow-up): the transfer's demote is a callback-skipping CAS
  # update_all (race-safety, by design — see transfer_ownership_to!), which
  # also skipped Trackable. A privilege demotion must still reach the audit
  # trail; written explicitly at the visibility a role change gets. Same
  # best-effort contract as Trackable#create_activity.
  def record_ownership_demotion(to_role)
    ActivityLog.create!(
      actor: Current.user,
      action: "membership.updated",
      trackable: self,
      workspace: workspace,
      visibility: "admin",
      metadata: { "changes" => { "role" => [ "owner", to_role.slug ] } }
    )
  rescue StandardError => e
    Rails.logger.warn("Activity tracking failed for Membership##{id} (transfer demote): #{e.message}")
    Rails.error.report(e, handled: true, context: { trackable: "Membership##{id}", action: "transfer_demote" })
  end

  # SEC-1 audit: a role change is a privilege event. Record the role slugs by
  # value (not the mutable role_id FK) and route it to the admin-only feed.
  def enrich_tracked_changes(changes)
    return changes unless changes.key?("role_id")
    from_id, to_id = changes["role_id"]
    slugs = Role.where(id: [ from_id, to_id ].compact).pluck(:id, :slug).to_h
    changes.merge("role" => [ slugs[from_id], slugs[to_id] ])
  end

  def activity_visibility(action)
    (action == "membership.updated" && saved_change_to_role_id?) ? "admin" : "workspace"
  end

  def notify_role_changed
    return if user.blank?
    WorkspaceRoleChangedNotifier.with(record: self).deliver(user)
  end

  # Pass `nil` to deliver — the Notifier's class-level `recipients` block is
  # responsible for resolving the (added user + owners) bucket and filtering by
  # in-app preference.
  def notify_member_added
    return if user.blank? || workspace.blank?
    WorkspaceMemberAddedNotifier.with(record: self).deliver(nil)
  end

  # Self-exclusion is the contract: the very first owner being seeded
  # (User#create_personal_workspace, bootstrap) must not count as a pre-existing owner.
  def workspace_has_other_owners?
    return false if workspace_id.blank?
    Membership.other_kept_owners(workspace_id, excluding: id).exists?
  end
end
