class Project < ApplicationRecord
  include Discardable
  include Tenanted
  include Trackable

  belongs_to :created_by, class_name: "User"
  has_many :project_memberships, dependent: :destroy
  has_many :users, through: :project_memberships
  has_many :invitations, as: :invitable, dependent: :destroy
  has_many :resources, dependent: :destroy
  has_one_attached :logo

  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validate :workspace_has_project_capacity, on: :create

  before_validation :generate_slug, if: -> { name.present? && (slug.blank? || (name_changed? && !slug_changed?)) }

  after_commit :broadcast_changes, on: [:create, :update]

  def to_param
    slug
  end

  def initials
    name.split.map(&:first).take(2).join.upcase
  end

  private

  def broadcast_changes
    broadcast_refresh_to workspace
  rescue => e
    Rails.logger.warn("Broadcast failed: #{e.message}")
  end

  def generate_slug
    base_slug = name.parameterize
    base_slug = "project-#{SecureRandom.hex(4)}" if base_slug.blank?
    self.slug = base_slug
    return unless workspace
    counter = 1
    while workspace.projects.where.not(id: id).exists?(slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def workspace_has_project_capacity
    return unless workspace
    workspace.lock!
    if workspace.projects.kept.count >= workspace.max_projects
      errors.add(:base, :workspace_project_limit, message: "workspace has reached its project limit")
    end
  end
end
