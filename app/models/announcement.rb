class Announcement < ApplicationRecord
  include Tenanted

  enum :slot, { home_page: "home_page", find_a_room_page: "find_a_room_page", about_page: "about_page" }
  has_rich_text :body

  validates :slot, presence: true, uniqueness: true
  validates :body, presence: true

  def self.for(slot) = find_by(slot: slot)
end
