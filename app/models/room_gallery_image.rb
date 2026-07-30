class RoomGalleryImage < ApplicationRecord
  include Tenanted
  include Describable

  belongs_to :room
  has_one_attached :image

  validates :position, numericality: { greater_than_or_equal_to: 0 }
  validates :image, attached: true, content_type: [ :png, :jpeg, :webp ],
                    size: { less_than_or_equal_to: 10.megabytes }

  # D9: no schema-level cap on gallery size — the UI enforces 5 (phase 4).
  scope :ordered, -> { order(position: :asc, id: :asc) }

  describable :image, derived_alt: ->(rec) {
    I18n.t("media.derived_alt.gallery_image", room: rec.room.display_name)
  }
end
