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
  has_one_attached :logo

  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validate :workspace_has_project_capacity, on: :create

  def to_param
    slug
  end

  def initials
    name.split.map(&:first).take(2).join.upcase
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

  def workspace_has_project_capacity
    return unless workspace
    workspace.lock!
    if workspace.projects.kept.count >= workspace.max_projects
      errors.add(:base, :workspace_project_limit, message: "workspace has reached its project limit")
    end
  end
end
