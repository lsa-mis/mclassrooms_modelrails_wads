class Membership < ApplicationRecord
  # Subclasses RecordInvalid so generic boundary rescues still catch it; controllers rescue the NAMED condition.
  class LastOwner < ActiveRecord::RecordInvalid; end

  include Discardable
  include Trackable
  include Broadcastable
  include Provenance
  include Ownership
  include Announcements

  belongs_to :user
  belongs_to :workspace
  belongs_to :role

  validates :user_id, uniqueness: { scope: :workspace_id }
  validate :workspace_has_member_capacity, on: :create

  # The real capacity guard is post-INSERT; the pre-flight lock! is a no-op across SQLite connections.
  # See /docs/developer/architecture (Concurrency).
  after_create :enforce_capacity_invariant

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

  # Mirror of Invitation.for_members_index; the two split one status filter — keep them in sync.
  scope :for_members_index, ->(role:, status:) {
    return none if status == "pending"

    includes(:user, :role)
      .filter_by_role(role)
      .filter_by_status(status)
  }

  def change_role!(new_role)
    demoting_owner = owner? && !new_role.owner?
    transaction do
      workspace.lock!
      update!(role: new_role)
      enforce_owner_floor! if demoting_owner
    end
  end

  def deactivate!(removed_by: nil)
    # Idempotence guard: MembersController#destroy resolves through the UNSCOPED association, so replays
    # land here. See /docs/developer/membership-lifecycle.
    return if discarded?

    self.removed_by = removed_by
    transaction do
      workspace.lock!
      validate_not_last_owner!
      discard!
      enforce_owner_invariant!
    end
  end

  # Deliberately NOT gated on Workspace#admittable? — archived workspaces still reactivate; pinned in
  # membership_spec. See /docs/developer/membership-lifecycle.
  def reactivate!(granted_by: nil, self_join: false)
    self.class.reject_conflicting_provenance!(granted_by: granted_by, self_join: self_join)
    self.granted_by = granted_by
    self.self_join = self_join
    undiscard!
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

  def track_creation
    metadata = { "role" => role&.slug }
    metadata["granted_by"] = granted_by.id if granted_by
    create_activity("membership.created", metadata.compact)
  end

  # Re-admission is an UPDATE that track_creation never sees, so the granter is merged here.
  # See /docs/developer/membership-lifecycle.
  def tracked_update_metadata(changes)
    return super unless just_reactivated? && granted_by

    super.merge("granted_by" => granted_by.id)
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

  # Discarded → kept. Direction matters: the same column change in the other
  # direction is a removal.
  def just_reactivated?
    saved_change_to_discarded_at? && discarded_at.nil?
  end

  # The before-value matters: a re-stamp on an already-removed row is not a removal.
  def just_deactivated?
    saved_change_to_discarded_at? && discarded_at.present? && discarded_at_before_last_save.nil?
  end
end
