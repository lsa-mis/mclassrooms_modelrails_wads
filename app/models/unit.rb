class Unit < ApplicationRecord
  include Tenanted

  validates :department_group, presence: true, uniqueness: { scope: :workspace_id }

  def display_name
    UnitDisplayName.where(workspace_id: workspace_id).find_by(department_group: department_group)&.display_name ||
      description.presence || department_group
  end
end
