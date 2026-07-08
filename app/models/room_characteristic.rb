class RoomCharacteristic < ApplicationRecord
  include Tenanted

  belongs_to :room

  validates :code, presence: true, uniqueness: { scope: :room_id }
  validates :short_code, presence: true
end
