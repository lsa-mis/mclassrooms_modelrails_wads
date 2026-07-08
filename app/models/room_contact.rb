class RoomContact < ApplicationRecord
  include Tenanted

  belongs_to :room

  validates :room_id, uniqueness: true
end
