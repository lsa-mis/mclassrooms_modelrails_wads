class Building < ApplicationRecord
  include Tenanted

  belongs_to :campus, optional: true
  belongs_to :hidden_by, class_name: "User", optional: true
  has_many :rooms, dependent: :destroy
  has_many :floors, dependent: :destroy
  has_many :notes, as: :notable, dependent: :destroy
  has_one_attached :photo

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
