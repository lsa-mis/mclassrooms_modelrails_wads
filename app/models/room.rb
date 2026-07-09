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

  SEARCH_INDEX_TABLE = "room_search_index"
  SEARCH_INDEX_COLUMNS = %w[facility_code nickname room_number rmrecnbr building_name].freeze

  after_save :refresh_search_index        # same-transaction: FTS lives in the same SQLite file
  after_destroy :remove_from_search_index

  # D8 classroom rule as a display scope; D6 visibility split (duplicated on
  # Building by design — see plan constraints).
  scope :classroom, -> {
    where(room_type: "Classroom").where.not(facility_code: nil)
      .where(instructional_seat_count: 2..)
  }
  scope :listed,      -> { where(in_feed: true, hidden_at: nil) }
  scope :hidden,      -> { where.not(hidden_at: nil) }
  scope :not_in_feed, -> { where(in_feed: false) }

  # Phase 4 Task 6 (Brief §5.3): the room-number natural sort extracted out of
  # RoomSearch::DEFAULT_ORDER's tail (app/lib/room_search.rb:33-34) so the
  # floor-plan view's same-floor room list orders identically to Find a Room
  # without a second, drift-prone copy of the CAST/COLLATE expression. SQLite's
  # CAST stops at the first non-digit, so a lettered-prefix number like "B100"
  # casts to 0 and sorts before "100"; the COLLATE NOCASE tiebreak then
  # alpha-orders same-cast labels. Mirrors DEFAULT_ORDER's tail exactly — keep
  # the two in sync if either changes.
  scope :natural_room_order, -> { order(Arel.sql("CAST(room_number AS INTEGER), room_number COLLATE NOCASE")) }

  # D8 characteristic filter: AND semantics — rooms having ALL given
  # short_codes, not merely any. COUNT(DISTINCT ...) guards against both a
  # duplicated short_code in the caller's array and a room with two
  # RoomCharacteristic rows sharing a short_code under different raw codes.
  scope :with_all_characteristics, ->(short_codes) {
    codes = Array(short_codes).compact_blank.uniq
    next all if codes.empty?
    joins(:room_characteristics)
      .where(room_characteristics: { short_code: codes })
      .group("rooms.id")
      .having("COUNT(DISTINCT room_characteristics.short_code) = ?", codes.size)
  }

  # Delegates to the shared CodeNormalizer (app/lib) so facility codes and
  # characteristic short codes normalize identically — behavior unchanged
  # (downcase, strip non-alphanumeric, blank -> nil).
  def self.normalize_facility_code(value)
    CodeNormalizer.normalize(value)
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

  # Prefix-match FTS5 query; tokens are quoted so input can't inject MATCH syntax.
  def self.search_name(q)
    match = q.to_s.scan(/[[:alnum:]]+/).map { |t| %("#{t}"*) }.join(" ")
    return none if match.blank?
    where(id: connection.select_values(sanitize_sql_array(
      [ "SELECT rowid FROM #{SEARCH_INDEX_TABLE} WHERE #{SEARCH_INDEX_TABLE} MATCH ?", match ]
    )))
  end

  def self.rebuild_search_index!
    connection.execute("DELETE FROM #{SEARCH_INDEX_TABLE}")
    find_each { |record| record.send(:refresh_search_index) }
  end

  private

  def normalize_facility_code
    self.facility_code_normalized = self.class.normalize_facility_code(facility_code)
  end

  def refresh_search_index
    remove_from_search_index
    self.class.connection.execute(self.class.sanitize_sql_array([
      "INSERT INTO #{SEARCH_INDEX_TABLE}(rowid, #{SEARCH_INDEX_COLUMNS.join(', ')}) VALUES (?, ?, ?, ?, ?, ?)",
      id, facility_code, nickname, room_number, rmrecnbr, building_name
    ]))
  end

  def remove_from_search_index
    self.class.connection.execute(
      self.class.sanitize_sql_array([ "DELETE FROM #{SEARCH_INDEX_TABLE} WHERE rowid = ?", id ])
    )
  end
end
