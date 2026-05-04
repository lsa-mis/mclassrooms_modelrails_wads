class Membership < ApplicationRecord
  include Discardable
  include Trackable
  include Broadcastable

  belongs_to :user
  belongs_to :workspace
  belongs_to :role

  validates :user_id, uniqueness: { scope: :workspace_id }
  validate :workspace_has_member_capacity, on: :create

  # Notify the affected user whenever their role within the workspace changes.
  # Uses saved_change_to_role_id? rather than role_id_previously_changed? so it
  # also fires correctly under nested transactions where dirty tracking can lag.
  after_update_commit :notify_role_changed, if: :saved_change_to_role_id?

  # Notify the new member + workspace owners whenever a fresh membership is created.
  # `deliver(nil)` defers recipient resolution to the Notifier's `recipients` block.
  #
  # Gated by `workspace_has_other_owners?` — a workspace without owners *other
  # than this membership* (e.g. User#create_personal_workspace seeding the very
  # first owner-membership, or bare-bones test factories that build a workspace
  # + non-owner membership but never seed an owner) has nobody for whom the
  # "new member joined" event is actionable. Firing in that scenario produces
  # a self-notification at best, and pollutes adjacent specs that exercise
  # Membership creation as setup.
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

  def change_role!(new_role)
    update!(role: new_role)
  end

  def deactivate!
    transaction do
      workspace.lock!
      validate_not_last_owner!
      discard!
      ProjectMembership.joins(:project)
        .where(projects: { workspace_id: workspace_id }, user_id: user_id)
        .destroy_all
    end
  end

  def reactivate!
    undiscard!
  end

  def transfer_ownership_to!(target_membership)
    owner_role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" }
    admin_role = Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" }

    transaction do
      workspace.lock!
      reload
      raise ActiveRecord::RecordInvalid, self unless role.slug == "owner"
      target_membership.reload
      target_membership.update!(role: owner_role)
      update!(role: admin_role)
    end
  end

  private

  def broadcast_target
    workspace
  end

  def workspace_has_member_capacity
    return unless workspace
    workspace.lock!
    if workspace.memberships.kept.count >= workspace.max_members
      errors.add(:base, :workspace_member_limit)
    end
  end

  def validate_not_last_owner!
    if role.slug == "owner" && workspace.memberships.kept.joins(:role).where(roles: { slug: "owner" }).count <= 1
      errors.add(:base, :last_owner)
      raise ActiveRecord::RecordInvalid, self
    end
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

  # True when at least one OTHER kept owner-role membership exists in the
  # workspace at the moment of after_create_commit. The `where.not(id: id)`
  # self-exclusion is load-bearing: it ensures the very first owner being
  # seeded (User#create_personal_workspace, bootstrap) is not treated as
  # having a pre-existing owner. The method name surfaces this — "OTHER
  # owners" — so a future reader of the `if:` callback option immediately
  # understands that self-exclusion is the contract, not an accident.
  # Owners-from-other-workspaces are correctly excluded by the workspace_id scope.
  def workspace_has_other_owners?
    return false if workspace_id.blank?
    Membership.kept
      .joins(:role)
      .where(workspace_id: workspace_id)
      .where(roles: { slug: "owner" })
      .where.not(id: id)
      .exists?
  end
end
