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
  has_many :saved_rooms, dependent: :destroy
  has_one_attached :photo
  # :poster is the pano pane's static preview AND the ingest task's eager
  # pre-processing target (PanoramaIngest) — named here so one definition
  # serves both and the first visitor never pays the vips transform.
  has_one_attached :panorama do |attachable|
    attachable.variant :poster, resize_to_limit: [ 1024, 512 ], format: :webp
  end
  has_one_attached :seating_chart

  # Phase 4 Task 7 (Brief §5.3): admin gallery add/remove/reorder flows through
  # nested attributes so the whole edit form — curated fields AND gallery
  # changes — resolves to one `attributes:` hash for Curation::Apply.call, no
  # separate save. allow_destroy: true backs the `_destroy` checkbox per row.
  #
  # reject_if is a necessary addition beyond the brief's one-line snippet: the
  # edit view renders blank "add another photo" rows up to the D9 five-image
  # cap, each pre-filled with a `position` value so a real upload lands in the
  # right slot without extra JS. Without reject_if, `position` being non-blank
  # on an UNTOUCHED blank row defeats Rails' own `all_blank?` skip, so
  # `assign_nested_attributes_for_collection_association` would build a new
  # RoomGalleryImage with no image attached — RoomGalleryImage's own
  # `validates :image, attached: true` would then fail EVERY curated-field-only
  # edit (e.g. a plain nickname change) with an unrelated gallery error.
  #
  # Reject ONLY a NEW row (no `id`) with a blank `image` — an existing row's
  # reorder/destroy submission never resends an `image` key at all (no
  # re-upload), and `call_reject_if` in Rails' own nested_attributes.rb runs
  # for id-bearing (update) hashes too, not just new ones — an `image`-blank
  # check alone would silently no-op every position/`_destroy` edit on an
  # existing gallery image. `with_indifferent_access` tolerates either string
  # keys (real form submissions) or symbol keys (specs/console calls).
  accepts_nested_attributes_for :gallery_images, allow_destroy: true,
    reject_if: proc { |attributes|
      attrs = attributes.with_indifferent_access
      attrs[:id].blank? && attrs[:image].blank?
    }

  validates :rmrecnbr, presence: true, uniqueness: true
  validates :photo, :panorama, content_type: [ :png, :jpeg, :webp ],
                    size: { less_than_or_equal_to: 10.megabytes }
  validates :seating_chart, content_type: [ :png, :jpeg, :webp, :pdf ],
                    size: { less_than_or_equal_to: 10.megabytes }

  before_save :normalize_facility_code

  # Phase 4 Task 7 (Brief §5.3): attribute-shaped removers so a media "delete"
  # checkbox flows through strong params + Curation::Apply.call(attributes:)
  # exactly like nickname/ada_seat_count — no separate purge call in the
  # controller. purge_later (not purge) is a deliberate MVP choice: it's
  # enqueued as a side effect of #assign_attributes, which runs BEFORE
  # Curation::Apply's transaction opens, so on the rare rollback (the audit
  # write itself failing) the purge job still executes even though the rest of
  # the mutation rolled back. Acceptable for MVP; flagged in the task report.
  # The reader always returns false (never true) so the checkbox round-trips
  # unchecked on re-render (a validation failure re-renders :edit) rather than
  # echoing back "checked" from a transient submitted value.
  %i[photo panorama seating_chart].each do |slot|
    define_method("remove_#{slot}=") do |value|
      public_send(slot).purge_later if ActiveModel::Type::Boolean.new.cast(value)
    end
    define_method("remove_#{slot}") { false }
  end

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

  # URL param: rooms are addressed by their stable rmrecnbr (the U-M-wide,
  # unique, non-null natural key) rather than the serial id, so /rooms/:id URLs
  # are stable and meaningful. RoomsController#set_room finds by rmrecnbr to match.
  def to_param = rmrecnbr

  def display_name
    base = facility_code.presence || [ building_name, room_number ].compact_blank.join(" ")
    nickname.present? ? "#{base} – #{nickname}" : base
  end

  def hidden? = hidden_at.present?

  # Phase 5 Task 5 (Brief §14.1): the one-way editor hide / admin unhide
  # flow. Both mutations are real column changes (hidden_at/hidden_by), so
  # Curation::Apply's `before_after` diff captures them without any special
  # casing (unlike the attachment writers above, whose diff is always
  # empty). `hidden_by: actor` assigns the belongs_to directly — no
  # `_id` juggling needed since `actor` is already a User.
  def hide!(actor:)
    Curation::Apply.call(record: self, actor: actor, action: "room.hidden",
                         attributes: { hidden_at: Time.current, hidden_by: actor })
  end

  def unhide!(actor:)
    Curation::Apply.call(record: self, actor: actor, action: "room.unhidden",
                         attributes: { hidden_at: nil, hidden_by: nil })
  end

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
