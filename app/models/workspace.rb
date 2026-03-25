class Workspace < ApplicationRecord
  include Discardable

  has_one_attached :logo
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :roles
  has_many :invitations, as: :invitable, dependent: :destroy

  enum :plan, { free: "free", pro: "pro", enterprise: "enterprise" }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug, if: -> { name.present? && (slug.blank? || (name_changed? && !slug_changed?)) }

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

  def generate_slug
    base_slug = name.parameterize
    self.slug = base_slug
    counter = 1
    while Workspace.where.not(id: id).exists?(slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end
end
