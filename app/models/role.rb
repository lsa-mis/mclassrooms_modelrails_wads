class Role < ApplicationRecord
  belongs_to :workspace, optional: true
  has_many :memberships, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validate :permissions_must_be_valid_shape

  scope :system_defaults, -> { where(workspace_id: nil) }

  # Canonical definitions for the global (workspace_id: nil) roles. Single
  # source of truth shared by db/seeds.rb and every request-time lookup —
  # before this existed, call sites each carried their own copy and could
  # create the same role with divergent permissions depending on who won.
  SYSTEM_DEFAULTS = {
    "owner"  => { name: "Owner",  permissions: { "manage_workspace" => true, "manage_members" => true, "manage_projects" => true, "manage_settings" => true } },
    "admin"  => { name: "Admin",  permissions: { "manage_members" => true, "manage_projects" => true, "manage_settings" => true } },
    "member" => { name: "Member", permissions: { "manage_projects" => true } },
    "viewer" => { name: "Viewer", permissions: {} }
  }.freeze

  # find_or_create_by! is find-then-create, not atomic: two concurrent
  # callers can both miss the find and race the INSERT. The partial unique
  # index (slug WHERE workspace_id IS NULL) makes the loser raise
  # RecordNotUnique instead of inserting a duplicate — re-find and return
  # the winner's row.
  def self.system_default!(slug)
    slug = slug.to_s
    defaults = SYSTEM_DEFAULTS.fetch(slug)
    find_or_create_by!(slug: slug, workspace_id: nil) do |role|
      role.name = defaults[:name]
      role.permissions = defaults[:permissions]
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(slug: slug, workspace_id: nil)
  end

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
