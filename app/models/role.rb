class Role < ApplicationRecord
  belongs_to :workspace, optional: true
  has_many :memberships, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }

  scope :system_defaults, -> { where(workspace_id: nil) }
end
