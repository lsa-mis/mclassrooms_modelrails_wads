class Workspace < ApplicationRecord
  include Discardable
  include Trackable

  has_one_attached :logo
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :roles
  has_many :invitations, as: :invitable, dependent: :destroy
  has_many :projects, dependent: :destroy

  enum :plan, { free: "free", pro: "pro", enterprise: "enterprise" }

  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: true
  validates :max_members, numericality: { greater_than: 0 }
  validates :max_projects, numericality: { greater_than: 0 }

  before_validation :generate_slug, if: -> { name.present? && (slug.blank? || (name_changed? && !slug_changed?)) }

  after_commit :broadcast_changes, on: [:update]

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

  def effective_roles
    Role.where(workspace_id: [nil, id])
  end

  private

  def broadcast_changes
    broadcast_refresh_to self
  rescue => e
    Rails.logger.warn("Broadcast failed: #{e.message}")
  end

  def generate_slug
    base_slug = name.parameterize
    base_slug = "workspace-#{SecureRandom.hex(4)}" if base_slug.blank?
    self.slug = base_slug
    counter = 1
    while Workspace.where.not(id: id).exists?(slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end
end
