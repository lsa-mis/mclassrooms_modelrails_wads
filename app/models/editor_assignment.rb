class EditorAssignment < ApplicationRecord
  include Tenanted

  # Consumed only by RoleResolver (phase 5). Uniqueness is scoped to unit_id
  # only, not also workspace_id — same pattern as RoomCharacteristic/Floor:
  # the natural-key parent (unit) already pins the tenant, so double-scoping
  # by workspace would be redundant (single shared workspace, D1).
  belongs_to :user
  belongs_to :unit

  validates :user_id, uniqueness: { scope: :unit_id }
end
