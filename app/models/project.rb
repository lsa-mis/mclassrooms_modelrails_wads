class Project < ApplicationRecord
  include Discardable
  include Archivable
  include Tenanted
  include Trackable
  include Broadcastable
  include Sluggable

  belongs_to :created_by, class_name: "User"
  has_many :project_memberships, dependent: :destroy
  has_many :users, through: :project_memberships
  has_many :invitations, as: :invitable, dependent: :destroy
  has_many :resources, dependent: :destroy
  has_many :client_accesses, dependent: :destroy
  has_one_attached :logo

  attribute :enabled_tools, :json, default: nil

  before_create :default_enabled_tools

  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validate :workspace_has_project_capacity, on: :create

  # A project is visible to external clients only while it — and its
  # workspace — are kept and the workspace is not suspended (locked).
  # Archived (project OR workspace) still shows: archived keeps existing
  # collaborators, and clients are collaborators on a specific project.
  scope :client_accessible, -> {
    kept.where(workspace: Workspace.kept.not_suspended)
  }

  def to_param
    slug
  end

  def initials
    name.split.map(&:first).take(2).join.upcase
  end

  # See Workspace#status — Project has no suspended branch (Suspendable is
  # workspace-only; a locked workspace gates everything inside it).
  def status
    case [ discarded_at, archived_at ]
    in [ Time, * ]  then :discarded
    in [ _, Time ]  then :archived
    else                 :active
    end
  end

  # Guarded like Workspace's mutators (see comments there). The suspended
  # guard reads through the association — lock! clears the association
  # cache, so workspace.suspended? re-reads committed state under the lock.
  def archive!
    transaction do
      lock!
      next if archived?
      raise Suspendable::SuspendedError if workspace.suspended?
      super
    end
  end

  def unarchive!
    transaction do
      lock!
      next unless archived?
      raise Suspendable::SuspendedError if workspace.suspended?
      super
    end
  end

  def discard!
    transaction do
      lock!
      next if discarded?
      raise Suspendable::SuspendedError if workspace.suspended?
      super
    end
  end

  def tool_enabled?(key)
    (enabled_tools || []).include?(key.to_s)
  end

  # Registry tools that are both implemented and enabled for this project,
  # in registry order — what the project tab bar renders.
  def tools
    ProjectTools::Registry.implemented.select { |tool| tool_enabled?(tool.key) }
  end

  def client?(user)
    client_accesses.kept.exists?(user: user)
  end

  def client_accessible?
    kept? && workspace.kept? && !workspace.suspended?
  end

  def client_visible_resources
    resources.kept.published.where(shared_with_client: true).positioned
  end

  private

  def broadcast_target
    workspace
  end

  # Slugs are unique within a workspace, not globally
  def slug_taken?(candidate)
    return false unless workspace
    workspace.projects.where.not(id: id).exists?(slug: candidate)
  end

  def default_enabled_tools
    self.enabled_tools = ProjectTools::Registry.default_keys if enabled_tools.nil?
  end

  def workspace_has_project_capacity
    return unless workspace
    workspace.lock!
    if workspace.projects.kept.count >= workspace.max_projects
      errors.add(:base, :workspace_project_limit)
    end
  end
end
