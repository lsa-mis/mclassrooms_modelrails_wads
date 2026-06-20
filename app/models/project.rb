class Project < ApplicationRecord
  include Discardable
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

  def to_param
    slug
  end

  def initials
    name.split.map(&:first).take(2).join.upcase
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
