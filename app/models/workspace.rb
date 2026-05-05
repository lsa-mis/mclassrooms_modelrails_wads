class Workspace < ApplicationRecord
  include Discardable
  include Trackable
  include Broadcastable
  include Sluggable

  has_one_attached :logo
  has_one_attached :logo_original
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :roles, dependent: :destroy
  has_many :invitations, as: :invitable, dependent: :destroy
  has_many :projects, dependent: :destroy

  enum :plan, { free: "free", pro: "pro", enterprise: "enterprise" }

  validates :name, presence: true, length: { maximum: 255 }
  validates :logo,
    content_type: %w[image/png image/jpeg image/gif image/webp],
    size: { less_than: 5.megabytes }
  validates :logo_original,
    content_type: %w[image/png image/jpeg image/gif image/webp],
    size: { less_than: 10.megabytes }
  validates :slug, presence: true, uniqueness: true
  validates :max_members, numericality: { greater_than: 0 }
  validates :max_projects, numericality: { greater_than: 0 }
  validates :primary_color, inclusion: { in: 0..360 }, allow_nil: true
  validates :logo_source, inclusion: { in: %w[upload initials] }

  def self.broadcast_events
    [ :update ]
  end

  def discard!
    transaction do
      super
      projects.kept.find_each(&:discard!)
    end
  end

  def to_param
    slug
  end

  def initials
    name.split.map(&:first).take(2).join.upcase
  end

  def owner
    # Uses detect (not joins + find_by) so it works from preloaded
    # memberships without firing a per-row query in list views.
    memberships.detect { |m| m.role.slug == "owner" }&.user
  end

  # Returns all User records currently holding an owner-role kept membership
  # in this workspace. Used by the capacity-approaching sweep to broadcast a
  # billing alert to every owner, and exposed for future ownership-management
  # UIs that need the full owner roster (vs. `#owner`, which returns just one).
  #
  # The query joins :role and filters by slug "owner", scoped to global
  # ("workspace_id IS NULL") and workspace-scoped owner-named roles. This
  # mirrors the resolver in WorkspaceMemberAddedNotifier and the membership
  # validation in Membership#validate_not_last_owner!. `.includes(:user)`
  # preloads the user side so callers iterating `.owners.each { |u| ... }`
  # don't N+1.
  def owners
    memberships
      .kept
      .joins(:role)
      .where(roles: { slug: "owner" })
      .includes(:user)
      .map(&:user)
      .compact
  end

  def available_logo_sources
    %w[upload initials]
  end

  def effective_roles
    Role.where(workspace_id: [ nil, id ])
  end

  private
end
