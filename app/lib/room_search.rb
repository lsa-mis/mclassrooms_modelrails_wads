# Query object behind Find a Room (Brief §5.2). One instance per request.
class RoomSearch
  DEFAULT_PER_PAGE = 30
  MAX_PER_PAGE     = 100
  SORTS            = %w[default capacity_asc capacity_desc].freeze
  FALLBACK_CAPACITY_BOUND = 600 # pre-first-sync only; Setting wins (D12)

  # Sort is SQL, not Ruby: it must compose with LIMIT/OFFSET pagination.
  # Lettered floors ("B", "M") sort before numeric ("2" < "10" naturally via
  # CAST); rooms without a floor sort last within their building. Room numbers
  # natural-sort by leading integer (SQLite CAST stops at the first non-digit;
  # "B100" casts to 0 and resolves on the NOCASE alpha tiebreak).
  #
  # The lettered bucket ALSO natural-sorts labels that carry digits ("B2" <
  # "B10", not the alphabetical "B10" < "B2"): it splits each label into an
  # alpha prefix (rtrim the trailing digits) and a numeric suffix (ltrim the
  # leading letters, then CAST). SQLite's rtrim/ltrim second arg is a *character
  # set*, so `rtrim(label, '0-9')` drops the trailing number and `ltrim(label,
  # 'A-Za-z')` drops the leading letters — both pure-SQL, no regex/UDF. A
  # pure-numeric label ("10") rtrims to "" and a pure-alpha one ("M") ltrims to
  # "" → CAST 0, but the 0/1/2 bucket above already isolates those, so these two
  # keys only ever tiebreak *within* the lettered bucket.
  ALPHA_CHARS = ("A".."Z").to_a.join + ("a".."z").to_a.join
  DEFAULT_ORDER = Arel.sql(<<~SQL.squish).freeze
    buildings.name COLLATE NOCASE,
    CASE WHEN floors.label IS NULL THEN 2
         WHEN floors.label GLOB '[0-9]*' THEN 1
         ELSE 0 END,
    CASE WHEN floors.label GLOB '[0-9]*' THEN CAST(floors.label AS INTEGER) END,
    rtrim(floors.label, '0123456789') COLLATE NOCASE,
    CAST(ltrim(floors.label, '#{ALPHA_CHARS}') AS INTEGER),
    floors.label COLLATE NOCASE,
    CAST(rooms.room_number AS INTEGER),
    rooms.room_number COLLATE NOCASE
  SQL

  # `params = {}, **rest` (rather than a single positional `params`) is
  # required, not stylistic: Ruby 3+ treats a bare `RoomSearch.new(building:
  # "Mason", ...)` call as pure keyword arguments against the declared `base:`
  # keyword, not as an implicit positional Hash — with only `params, base:`
  # that raises ArgumentError before any keyword is even matched. Accepting an
  # optional positional Hash *and* `**rest` lets both call shapes work: a
  # controller's `RoomSearch.new(params, base: scope)` (positional) and this
  # object's own bare-keyword call sites / specs (`RoomSearch.new(building:
  # "Mason", capacity_min: "40")`) drop into `rest` and merge in identically.
  def initialize(params = {}, base: Room.classroom.listed, **rest)
    @params = params.to_h.merge(rest).symbolize_keys
    @base   = base
  end

  def results
    scope = @base.joins(:building).left_outer_joins(:floor)
                 .preload(:building, :floor, :unit, :room_characteristics,
                          gallery_images: { image_attachment: :blob })
    scope = filter_building(scope)
    scope = filter_room_name(scope)
    scope = scope.where(unit_id: @params[:unit_id]) if @params[:unit_id].present?
    scope = filter_capacity(scope)
    scope = scope.merge(Room.with_all_characteristics(characteristic_codes)) if characteristic_codes.any?
    apply_sort(scope)
  end

  def per_page
    per = @params[:per].to_i
    per.positive? ? [ per, MAX_PER_PAGE ].min : DEFAULT_PER_PAGE
  end

  def sort = SORTS.include?(@params[:sort]) ? @params[:sort] : "default"

  # Memoized per instance: bounded_max?/capacity_max/capacity_summary all read
  # it, and the Task-4 view reads it again for the slider — without the memo
  # that's 4+ identical `Setting.capacity_filter_max` find_by queries per
  # request. A RoomSearch is built once per request, so the memo keeps the
  # "live" (never cross-request-cached) intent while collapsing the reads.
  def capacity_bound = @capacity_bound ||= (Setting.capacity_filter_max.presence || FALLBACK_CAPACITY_BOUND).to_i

  # "Building: mason, Capacity: 40-100, Filters: Lecture Capture" (Brief §5.2).
  # Unbounded endpoints (0 / bound) drop out of the label entirely.
  def summary
    parts = []
    parts << I18n.t("rooms.index.summary.building", value: @params[:building]) if @params[:building].present?
    parts << I18n.t("rooms.index.summary.room", value: @params[:room]) if @params[:room].present?
    parts << I18n.t("rooms.index.summary.unit", value: unit.display_name) if unit
    parts << capacity_summary if capacity_summary
    if characteristic_codes.any?
      # Resolve the short_code => label hash ONCE rather than calling
      # label_for per selected code: label_for computes data_version (4
      # aggregate queries) to build its cache key, so N selected
      # characteristics meant N redundant data_version computations here.
      labels = CharacteristicFilterGroups.labels
      parts << I18n.t("rooms.index.summary.characteristics",
                       value: characteristic_codes.map { |c| labels.fetch(c, c) }.join(", "))
    end
    parts.join(I18n.t("rooms.index.summary.separator"))
  end

  # Dropdown source: distinct units present in listed classrooms (Brief §5.2).
  # Ruby sort is fine HERE (small fixed set), unlike the room sort.
  def self.unit_options
    Unit.where(id: Room.classroom.listed.select(:unit_id).distinct).sort_by(&:display_name)
  end

  private

  def filter_building(scope)
    return scope if @params[:building].blank?
    scope.where(building_id: Building.search_name(@params[:building]).select(:id))
  end

  # FTS vector OR normalized facility-code substring OR nickname substring
  # ("mlb1200" and "Aud 3" both work — Brief §5.2). SQLite's LIKE is already
  # ASCII-case-insensitive, so the comparison works regardless of case:
  # facility_code_normalized is lowercased at write time (CodeNormalizer), and
  # the query side is uppercased here purely for readability — either casing
  # matches the same rows.
  def filter_room_name(scope)
    q = @params[:room].to_s.strip
    return scope if q.blank?
    code = "%#{Room.sanitize_sql_like(q.gsub(/\s+/, '').upcase)}%"
    nick = "%#{Room.sanitize_sql_like(q)}%"
    scope.merge(
      Room.where(id: Room.search_name(q).select(:id))
          .or(Room.where("rooms.facility_code_normalized LIKE ?", code))
          .or(Room.where("rooms.nickname LIKE ?", nick))
    )
  end

  def filter_capacity(scope)
    scope = scope.where(instructional_seat_count: capacity_min..) if capacity_min.positive?
    scope = scope.where(instructional_seat_count: ..capacity_max) if bounded_max?
    scope
  end

  def capacity_min = @params[:capacity_min].to_i
  def capacity_max = @params[:capacity_max].present? ? @params[:capacity_max].to_i : capacity_bound
  def bounded_max? = capacity_max < capacity_bound

  def capacity_summary
    return I18n.t("rooms.index.summary.capacity_range", min: capacity_min, max: capacity_max) if capacity_min.positive? && bounded_max?
    return I18n.t("rooms.index.summary.capacity_min_only", min: capacity_min) if capacity_min.positive?
    return I18n.t("rooms.index.summary.capacity_max_only", max: capacity_max) if bounded_max?
    nil
  end

  # Normalized via the shared CodeNormalizer (defense): CharacteristicFilterGroups
  # (Task 3) passes already-normalized short_codes drawn from CharacteristicDisplayRule,
  # and the characteristics sync (phase 2) normalizes RoomCharacteristic.short_code the
  # same way — but a raw/differently-cased code reaching this object directly (e.g. a
  # hand-built query string) must still resolve to the same normalized form so
  # Room.with_all_characteristics' plain equality match still hits.
  def characteristic_codes = Array(@params[:characteristics]).filter_map { |c| CodeNormalizer.normalize(c) }
  def unit = @params[:unit_id].present? ? Unit.find_by(id: @params[:unit_id]) : nil

  def apply_sort(scope)
    case sort
    when "capacity_asc"  then scope.order(instructional_seat_count: :asc).order(DEFAULT_ORDER)
    when "capacity_desc" then scope.order(instructional_seat_count: :desc).order(DEFAULT_ORDER)
    else scope.order(DEFAULT_ORDER)
    end
  end
end
