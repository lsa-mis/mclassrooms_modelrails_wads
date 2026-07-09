class Building < ApplicationRecord
  include Tenanted

  belongs_to :campus, optional: true
  belongs_to :hidden_by, class_name: "User", optional: true
  has_many :rooms, dependent: :destroy
  has_many :floors, dependent: :destroy
  has_many :notes, as: :notable, dependent: :destroy
  has_one_attached :photo

  # Phase 4 Task 9 (Brief §5.3): the admin building-edit form's floors card
  # only attaches/replaces/removes each EXISTING floor's `plan` — floors are
  # sync-created (D10, Task 8), so this must never create or delete a `Floor`
  # row. No `allow_destroy: true` (there is no `_destroy` control on this
  # form), and reject_if skips a row where neither `plan` nor `remove_plan`
  # changed — mirroring Room's Task 7 reject_if, but the opposite direction:
  # Room's guard exists to tolerate BLANK pre-built "add another photo" rows;
  # this form never builds blank Floor rows at all (every `fields_for :floors`
  # row is an already-persisted floor), so the guard here is a plain no-op
  # skip for a row nothing touched, keeping an untouched floor row from
  # spuriously appearing in Curation::Apply's dirty-attribute diff.
  accepts_nested_attributes_for :floors,
    reject_if: proc { |attributes|
      attrs = attributes.with_indifferent_access
      attrs[:plan].blank? && attrs[:remove_plan].blank?
    }

  validates :bldrecnbr, presence: true, uniqueness: true
  validates :name, presence: true
  validates :photo, content_type: [ :png, :jpeg, :webp ],
                    size: { less_than_or_equal_to: 10.megabytes }

  SEARCH_INDEX_TABLE = "building_search_index"
  SEARCH_INDEX_COLUMNS = %w[name nickname abbreviation].freeze

  after_save :refresh_search_index        # same-transaction: FTS lives in the same SQLite file
  after_destroy :remove_from_search_index

  # D6 visibility split: in_feed sync-owned; hidden_at/hidden_by curation-owned.
  scope :listed,      -> { where(in_feed: true, hidden_at: nil) }
  scope :hidden,      -> { where.not(hidden_at: nil) }
  scope :not_in_feed, -> { where(in_feed: false) }
  scope :with_classrooms, -> { where(id: Room.classroom.select(:building_id)) }

  def display_name = nickname.present? ? "#{name} (#{nickname})" : name

  def hidden? = hidden_at.present?

  # Phase 4 Task 9 (Brief §5.3): attribute-shaped remover so a "delete photo"
  # checkbox flows through strong params + Curation::Apply.call(attributes:)
  # exactly like `nickname` — no separate purge call in the controller.
  # Mirrors Room's Task 7 remove_* writers (app/models/room.rb): purge_later
  # (not purge) runs as a side effect of #assign_attributes, which happens
  # BEFORE Curation::Apply's transaction opens, so the purge job still fires
  # even on the rare rollback where only the audit write fails. The reader
  # always returns false so the checkbox round-trips unchecked on a
  # validation-failure re-render rather than echoing back a transient
  # submitted value.
  def remove_photo=(value)
    photo.purge_later if ActiveModel::Type::Boolean.new.cast(value)
  end
  def remove_photo = false

  # Geocoding input for GeocodeBuildingJob (Task 8, phase 2 ingestion).
  # `state` and `zip` are joined with a space ("MI 48109") before being
  # comma-joined with the rest, matching conventional US postal address
  # formatting; any blank component (including a blank "state zip" pair)
  # is dropped rather than leaving a stray ", ,".
  def full_address
    [ address, city, [ state, zip ].compact_blank.join(" ").presence, country ].compact_blank.join(", ")
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

  def refresh_search_index
    remove_from_search_index
    self.class.connection.execute(self.class.sanitize_sql_array([
      "INSERT INTO #{SEARCH_INDEX_TABLE}(rowid, #{SEARCH_INDEX_COLUMNS.join(', ')}) VALUES (?, ?, ?, ?)",
      id, name, nickname, abbreviation
    ]))
  end

  def remove_from_search_index
    self.class.connection.execute(
      self.class.sanitize_sql_array([ "DELETE FROM #{SEARCH_INDEX_TABLE} WHERE rowid = ?", id ])
    )
  end
end
