class UnitDisplayName < ApplicationRecord
  include Tenanted

  validates :department_group, presence: true, uniqueness: { scope: :workspace_id }
  validates :display_name, presence: true
end
