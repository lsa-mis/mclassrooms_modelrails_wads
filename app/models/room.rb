class Room < ApplicationRecord
  include Tenanted

  belongs_to :building
  belongs_to :floor, optional: true
  belongs_to :campus, optional: true
  belongs_to :unit, optional: true
  belongs_to :hidden_by, class_name: "User", optional: true
  has_many :room_characteristics, dependent: :destroy  # satellite tables land in
  has_one :room_contact, dependent: :destroy           # Tasks 6/8/9; associations are
  has_many :gallery_images, class_name: "RoomGalleryImage", dependent: :destroy # lazy,
  has_many :availability_blocks, dependent: :destroy   # so the model loads before them
  has_many :notes, as: :notable, dependent: :destroy
  has_one_attached :photo
  has_one_attached :panorama
  has_one_attached :seating_chart

  validates :rmrecnbr, presence: true, uniqueness: true
  validates :photo, :panorama, content_type: [ :png, :jpeg, :webp ],
                    size: { less_than_or_equal_to: 10.megabytes }
  validates :seating_chart, content_type: [ :png, :jpeg, :webp, :pdf ],
                    size: { less_than_or_equal_to: 10.megabytes }

  before_save :normalize_facility_code

  # D8 classroom rule as a display scope; D6 visibility split (duplicated on
  # Building by design — see plan constraints).
  scope :classroom, -> {
    where(room_type: "Classroom").where.not(facility_code: nil)
      .where(instructional_seat_count: 2..)
  }
  scope :listed,      -> { where(in_feed: true, hidden_at: nil) }
  scope :hidden,      -> { where.not(hidden_at: nil) }
  scope :not_in_feed, -> { where(in_feed: false) }

  def self.normalize_facility_code(value)
    value.to_s.downcase.gsub(/[^a-z0-9]/, "").presence
  end

  def self.find_by_facility_code(q)
    normalized = normalize_facility_code(q)
    normalized && find_by(facility_code_normalized: normalized)
  end

  def display_name
    base = facility_code.presence || [ building_name, room_number ].compact_blank.join(" ")
    nickname.present? ? "#{base} – #{nickname}" : base
  end

  def hidden? = hidden_at.present?

  private

  def normalize_facility_code
    self.facility_code_normalized = self.class.normalize_facility_code(facility_code)
  end
end
