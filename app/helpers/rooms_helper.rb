# MiClassrooms Phase 3 Task 5 (Brief §5.2): Find a Room row helpers.
module RoomsHelper
  # Redesign (2026-07 sprint): short_codes promoted as always-visible "popular
  # features" chips in the filter card. A presentation choice (which filters
  # earn top billing), so it lives here; labels still come from the
  # admin-controlled display rules via the groups' own entries. Promoted codes
  # are EXCLUDED from the More-filters panel below so `characteristics[]` is
  # never rendered twice for one code (two same-name checked inputs would
  # double-submit).
  PROMOTED_FILTER_CODES = %w[projdigit movetablet whtbrd].freeze

  # Card tags (sprint prototype): a few LABELED tags beat a strip of ~15
  # ambiguous icons. Priority-ordered; capped in the view. The expanded
  # details still lists every characteristic.
  CARD_TAG_CODES = %w[projdigit lecturecap doccam whtbrd chkbrd teamtables instrcomp movetablet].freeze
  CARD_TAG_LIMIT = 4

  # Vendor building names arrive ALL CAPS ("CHEMISTRY AND DOW WILLARD H
  # LABORATORY"); humanize for display. Mixed-case (already-curated) names
  # pass through untouched. Single letters and known campus acronyms keep
  # their caps; small words downcase except in first position.
  BUILDING_ACRONYMS = %w[LSA EECS NUB USB UMMA SPH CCRB IM SEB BSRB GGBL EWRE FXB].freeze
  BUILDING_SMALL_WORDS = %w[AND OF THE FOR AT].freeze

  def humanized_building_name(building)
    name = building.display_name.to_s
    return name unless name == name.upcase

    name.split.map.with_index do |word, index|
      if BUILDING_ACRONYMS.include?(word) || word.length == 1 then word
      elsif BUILDING_SMALL_WORDS.include?(word) && index.positive? then word.downcase
      else word.capitalize
      end
    end.join(" ")
  end

  # Card title (sprint prototype: "1300 Chemistry"): a curated nickname wins
  # (display_name already prefers it), else room number + humanized building;
  # rooms without a number fall back to the facility-code display name.
  def room_card_title(room)
    return room.display_name if room.nickname.present? || room.room_number.blank?

    "#{room.room_number} #{humanized_building_name(room.building)}"
  end

  # Card meta (prototype: "LSA · 1st floor"): unit · floor. The building only
  # appears here when the title above fell back to a code and doesn't carry it.
  def room_card_meta(room)
    [ (humanized_building_name(room.building) if room.room_number.blank? && room.nickname.blank?),
      room.unit&.display_name,
      (t("rooms.row.floor_label", label: room.floor.label) if room.floor) ].compact.join(" · ")
  end

  def room_card_tags(room)
    codes = room.room_characteristics.map(&:short_code)
    CARD_TAG_CODES.select { |code| codes.include?(code) }
                  .first(CARD_TAG_LIMIT)
                  .map { |code| characteristic_labels.fetch(code, code) }
  end

  # Same override mechanism as characteristic_labels, for the vendor GROUP
  # names the More-filters panel uses as fieldset legends.
  def characteristic_group_name(group)
    I18n.t("rooms.characteristic_group_overrides.#{group.name}", default: group.name)
  end

  def promoted_filter_entries(filter_groups)
    filter_groups.flat_map(&:entries)
                 .select { |entry| PROMOTED_FILTER_CODES.include?(entry.short_code) }
                 .sort_by { |entry| PROMOTED_FILTER_CODES.index(entry.short_code) }
  end

  # [group, remaining_entries] pairs for the More-filters panel; groups whose
  # entries were all promoted drop out entirely.
  def panel_filter_groups(filter_groups)
    filter_groups.filter_map do |group|
      entries = group.entries.reject { |entry| PROMOTED_FILTER_CODES.include?(entry.short_code) }
      [ group, entries ] if entries.any?
    end
  end

  # How many applied filters live behind the More-filters disclosure —
  # panel-only characteristics plus unit and max capacity. Feeds the
  # summary's applied-count badge and the open-on-load rule below.
  def panel_filter_count(filter_params)
    (Array(filter_params[:characteristics]) - PROMOTED_FILTER_CODES).size +
      [ filter_params[:unit_id], filter_params[:capacity_max] ].count(&:present?)
  end

  # The More-filters disclosure opens on page load when it holds an applied
  # filter — a shared URL must not hide the state that produced its results.
  def more_filters_open?(filter_params) = panel_filter_count(filter_params).positive?

  # Applied-filter chips: RoomSearch#summary itemized — each part becomes a
  # link to the current search minus that one filter (plain GET links targeting
  # the results frame, the same pattern as the Reset link). `view`/`sort` ride
  # along untouched so removing a chip never resets an admin's inactive view or
  # the chosen sort.
  def filter_chips(filter_params)
    base = filter_params.to_h.symbolize_keys
    chips = []
    add = ->(label, without) { chips << [ label, find_a_room_path(without.compact_blank) ] }

    add.call(t("rooms.index.summary.query", value: base[:q].strip), base.except(:q)) if base[:q].present?
    add.call(t("rooms.index.summary.building", value: base[:building]), base.except(:building)) if base[:building].present?
    add.call(t("rooms.index.summary.room", value: base[:room]), base.except(:room)) if base[:room].present?
    if base[:unit_id].present? && (unit = Unit.find_by(id: base[:unit_id]))
      add.call(t("rooms.index.summary.unit", value: unit.display_name), base.except(:unit_id))
    end
    if base[:capacity_min].to_i.positive?
      add.call(t("rooms.index.summary.capacity_min_only", min: base[:capacity_min].to_i), base.except(:capacity_min))
    end
    if base[:capacity_max].present?
      add.call(t("rooms.index.summary.capacity_max_only", max: base[:capacity_max].to_i), base.except(:capacity_max))
    end
    Array(base[:characteristics]).each do |code|
      add.call(t("rooms.index.summary.characteristics", value: characteristic_labels.fetch(code, code)),
               base.merge(characteristics: Array(base[:characteristics]) - [ code ]))
    end
    chips
  end

  # Request-scoped memo of the full short_code => label map (mirrors
  # characteristic_icon_keys above): CharacteristicFilterGroups.labels computes
  # data_version (4 aggregates) to build its cache key, so calling label_for
  # per characteristic per row re-ran those aggregates hundreds of times per
  # render. Resolving the hash ONCE collapses that to a single computation.
  # Vendor labels (parsed from sync descriptions; CharacteristicDisplayRule
  # has no label column, so they are NOT admin-editable) get product-level
  # overrides from the locale — "Digital Data&Video" is a projector to every
  # user of this page.
  def characteristic_labels
    @characteristic_labels ||= CharacteristicFilterGroups.labels.merge(
      I18n.t("rooms.characteristic_label_overrides", default: {}).stringify_keys.transform_values(&:to_s)
    )
  end

  # First gallery image, position-ordered. Deliberately sorts the ALREADY
  # preloaded `gallery_images` array in Ruby rather than calling the `.ordered`
  # scope on the association: `.ordered.first` re-queries per room (bypassing
  # RoomSearch#results' preload), which Bullet's N+1 detector catches in test
  # (`config/environments/test.rb` sets `Bullet.raise = true`) — the
  # `unused_eager_loading` safelist entry for `Room`/`gallery_images` in
  # `lib/bullet_safelists.rb` exists precisely so this row can dereference the
  # preload without exercising `Room.gallery_images` from another code path
  # (the RoomSearch unit spec) — using `.ordered` here would defeat it.
  def room_thumbnail_image(room)
    room.gallery_images.sort_by { |image| [ image.position, image.id ] }.first
  end

  # Full characteristic label list for a row's expanded detail (Brief §5.2).
  def room_characteristic_labels(room)
    room.room_characteristics.map { |rc| characteristic_labels.fetch(rc.short_code, rc.short_code) }.sort
  end
end
