class Building < ApplicationRecord
  include Tenanted

  belongs_to :campus, optional: true
  belongs_to :hidden_by, class_name: "User", optional: true
  has_many :rooms, dependent: :destroy
  has_many :floors, dependent: :destroy
  has_many :notes, as: :notable, dependent: :destroy
  # Named variants so one definition serves the views AND the ingest task's
  # eager pre-processing (BuildingPhotoIngest — no visitor waits on a
  # multi-MB original): :hero is the building page figure, :thumb the edit
  # form preview.
  has_one_attached :photo do |attachable|
    attachable.variant :hero, resize_to_limit: [ 1600, 900 ], format: :webp
    attachable.variant :thumb, resize_to_fill: [ 150, 150 ], format: :webp
  end

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
  #
  # `attrs[:id].blank?` is checked FIRST and rejects unconditionally: unlike
  # Room's gallery (where a new, id-less row is the legitimate "add another
  # photo" case), this form's `fields_for :floors` only ever renders
  # already-persisted floor rows, so an id-less row can only be a forged/
  # tampered submission. Without this guard, an id-less row with a present
  # `plan` sails past the `plan.blank? && remove_plan.blank?` half of the
  # check and `assign_nested_attributes_for_collection_association` calls
  # `build` on `Floor` — a brand-new Floor row this form must never create.
  # (Today that `build` happens to be harmless-looking because unrelated
  # `label`/`workspace` validations fail it before save, but relying on
  # coincidental validation failure on ANOTHER model to enforce THIS model's
  # own invariant is exactly the gap this guard closes directly.)
  accepts_nested_attributes_for :floors,
    reject_if: proc { |attributes|
      attrs = attributes.with_indifferent_access
      attrs[:id].blank? || (attrs[:plan].blank? && attrs[:remove_plan].blank?)
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

  # Phase 5 Task 5 (Brief §14.1): admin-only hide/unhide, mirroring Room's
  # identical `#hide!`/`#unhide!` (app/models/room.rb) with the
  # `"building.*"` action strings. Buildings have no one-way editor
  # posture (BuildingPolicy#hide?/#unhide? are both admin-only) — these
  # exist purely so BuildingsController's actions have the same
  # attribute-assignment-via-Curation::Apply shape as Room's.
  def hide!(actor:)
    Curation::Apply.call(record: self, actor: actor, action: "building.hidden",
                         attributes: { hidden_at: Time.current, hidden_by: actor })
  end

  def unhide!(actor:)
    Curation::Apply.call(record: self, actor: actor, action: "building.unhidden",
                         attributes: { hidden_at: nil, hidden_by: nil })
  end

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
