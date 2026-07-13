# A user's shortlist entry: "I want to come back to this room." Pure join —
# no state beyond existence. Uniqueness is validated for friendly errors AND
# enforced by the DB's composite unique index (the controller uses
# create_or_find_by so a double-click race resolves to the winner's row).
class SavedRoom < ApplicationRecord
  include Tenanted

  belongs_to :user
  belongs_to :room

  validates :room_id, uniqueness: { scope: :user_id }
end
