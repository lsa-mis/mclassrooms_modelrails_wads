class Announcement < ApplicationRecord
  include Tenanted

  enum :slot, { home_page: "home_page", find_a_room_page: "find_a_room_page", about_page: "about_page" }
  has_rich_text :body

  # slot uniqueness is intentionally global (not scoped to workspace) even
  # though Announcement is Tenanted: slot is an app-internal page key, and
  # under the single-workspace posture (D1) one announcement per page is the
  # whole point. Announcement.for is a global find_by to match. If this app
  # ever became multi-tenant, scope this to workspace_id.
  validates :slot, presence: true, uniqueness: true
  validates :body, presence: true

  def self.for(slot) = find_by(slot: slot)
end
