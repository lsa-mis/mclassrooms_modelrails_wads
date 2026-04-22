class Role < ApplicationRecord
  belongs_to :workspace, optional: true
  has_many :memberships, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validate :permissions_must_be_valid_shape

  scope :system_defaults, -> { where(workspace_id: nil) }

  private

  def permissions_must_be_valid_shape
    return if permissions.blank?

    unless permissions.is_a?(Hash)
      errors.add(:permissions, "must be a hash")
      return
    end

    permissions.each do |key, value|
      unless key.is_a?(String)
        errors.add(:permissions, "keys must be strings")
        return
      end
      unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
        errors.add(:permissions, "values must be booleans")
        return
      end
    end
  end
end
