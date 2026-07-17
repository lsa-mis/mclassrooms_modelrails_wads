# MiClassrooms Phase 3 Task 5 (Brief §5.2): Find a Room row helpers.
module RoomsHelper
  # Redesign (2026-07 sprint): short_codes promoted as always-visible "popular
  # features" chips in the filter card. A presentation choice (which filters
  # earn top billing), so it lives here; labels still come from the
  # admin-controlled display rules via the groups' own entries. Promoted codes
  # are EXCLUDED from the More-filters panel below so `characteristics[]` is
  # never rendered twice for one code (two same-name checked inputs would
  # double-submit).
  # Taxonomy sweep (2026-07-12): projdigit swapped out — at 376/388 rooms
  # (97%) it filtered nothing; Interactive Screen splits the set near-evenly.
  # Phase 3: the movable-seating slot is a MERGED token (see
  # RoomSearch::MERGED_CHARACTERISTICS) — "can I move the furniture?" spans
  # two vendor codes, so the chip ORs across both.
  PROMOTED_FILTER_CODES = %w[intrscreen movableseating whtbrd].freeze

  # Card tags (sprint prototype): a few LABELED tags beat a strip of ~15
  # ambiguous icons. Priority-ordered; capped in the view. The expanded
  # details still lists every characteristic.
  CARD_TAG_CODES = %w[projdigit lecturecap doccam whtbrd chkbrd teamtables instrcomp movetablet].freeze
  CARD_TAG_LIMIT = 4

  # Near-universal characteristics (2026-07-16 corpus of 388 listed classrooms:
  # projdigit 97%, soundprgrm 95%, instrcomp 91%, lecturecap 83%, doccam 78%).
  # They sit on ~every room, so leading a card with them differentiates nothing —
  # every card read "Projector · Lecture Capture · Document Camera" (2026-07-15
  # panel). Demoted BELOW the distinctive chips so they fall into the "+N more"
  # disclosure, UNLESS the user is actively filtering on one (then it's exactly
  # what they asked for and stays emphasized — see #active_card_codes). Curated,
  # not computed at request time, so the ordering is stable across tests + prod.
  COMMON_CARD_CODES = %w[projdigit soundprgrm instrcomp lecturecap doccam].freeze

  # Vendor building names arrive ALL CAPS ("CHEMISTRY AND DOW WILLARD H
  # LABORATORY"); humanize for display. Mixed-case (already-curated) names
  # pass through untouched. Single letters and known campus acronyms keep
  # their caps; small words downcase except in first position.
  BUILDING_ACRONYMS = %w[LSA EECS NUB USB UMMA SPH CCRB IM SEB BSRB GGBL EWRE FXB].freeze
  BUILDING_SMALL_WORDS = %w[AND OF THE FOR AT].freeze

  def humanized_building_name(building)
    # A curated short_name wins outright (backlog #8): humanization makes
    # vendor names readable, only an admin can make them SHORT.
    return building.short_name if building.short_name.present?

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
  # Floor leads (audit, Fried): it's the token a person needs to find the
  # door; the long college name follows.
  def room_card_meta(room)
    [ (humanized_building_name(room.building) if room.room_number.blank? && room.nickname.blank?),
      (t("rooms.row.floor_label", label: room.floor.label) if room.floor),
      room.unit&.display_name ].compact.join(" · ")
  end

  # One-line identity meta for the room page's stage overlay / empty band:
  # building · Floor N · unit · type · N sq ft — only what exists.
  def room_meta_line(room)
    [ humanized_building_name(room.building),
      (t("rooms.row.floor_label", label: room.floor.label) if room.floor),
      room.unit&.display_name,
      room.room_type.presence,
      (t("rooms.show.square_feet_value", value: number_with_delimiter(room.square_feet)) if room.square_feet.present?) ]
      .compact.join(" · ")
  end

  # Card tags only earn their place when they DISCRIMINATE (audit, Fried:
  # four identical tags on every card carry no signal). The filterable set is
  # exactly the curated "questions people ask" list — demoted/ubiquitous
  # codes stay off the cards automatically as curation improves.
  def filterable_codes
    # Reuse the controller's @filter_groups when present — a fresh .filters
    # call recomputes the data_version cache key (4 aggregate queries), which
    # the query-budget spec rightly rejects.
    @filterable_codes ||= (@filter_groups || CharacteristicFilterGroups.filters)
                          .flat_map(&:entries).map(&:short_code).to_set
  end

  # ONE priority-ordered chip list for a results card (2026-07-14 redesign):
  # the same RoomPresenter::Chip objects the room page uses, ordered by a single
  # rule so the always-visible strip and the <details> remainder never diverge —
  # CARD_TAG_CODES differentiators first (fixed priority), then remaining
  # filterable characteristics alphabetically, then non-filterable ones. The view
  # slices .first(CARD_TAG_LIMIT) into the emphasized strip and .drop(CARD_TAG_LIMIT)
  # into the disclosure.
  def room_card_chips(room, active_codes: active_card_codes)
    card_chip_presenter(room).chips.sort_by { |chip| card_chip_sort_key(chip, active_codes) }
  end

  # The vendor codes the user is actively filtering on — merged filter tokens
  # (RoomSearch::MERGED_CHARACTERISTICS) expanded to their members so a card chip
  # (a vendor code) can match. A matched chip is emphasized first even if it's a
  # COMMON code — it's the contextual reason this card is in the results.
  def active_card_codes
    Array(params[:characteristics]).flat_map { |token|
      RoomSearch::MERGED_CHARACTERISTICS[token] || [ token ]
    }.to_set
  end

  # Reuse ONE CharacteristicDisplayRule index across every row (mirrors the
  # filterable_codes / @filter_groups memo): RoomPresenter's default runs
  # `.all.index_by` per instance, an N+1 Bullet raises on in test.
  def card_display_rules
    @card_display_rules ||= CharacteristicDisplayRule.all.index_by(&:short_code)
  end

  def card_chip_presenter(room)
    RoomPresenter.new(room, rules: card_display_rules)
  end

  # [tier, priority-within-tier, label, short_code]. Tiers, most-emphasized first:
  #   0 = ACTIVELY FILTERED codes (contextual — why this card matched)
  #   1 = distinctive CARD_TAG_CODES, fixed listed order
  #   2 = remaining filterable, alpha by label
  #   3 = non-filterable, alpha by label
  #   4 = COMMON_CARD_CODES (near-universal) — demoted into the "+N more" disclosure
  # The short_code tacked on last breaks ties between chips whose labels collide
  # after downcasing — Array#sort_by isn't stable, so without a unique tiebreaker
  # those chips could reorder between runs.
  def card_chip_sort_key(chip, active_codes = Set.new)
    code = chip.short_code
    return [ 0, CARD_TAG_CODES.index(code) || CARD_TAG_CODES.size, chip.label.downcase, code ] if active_codes.include?(code)
    return [ 4, 0, chip.label.downcase, code ] if COMMON_CARD_CODES.include?(code)

    if (index = CARD_TAG_CODES.index(code))
      [ 1, index, "", code ]
    elsif filterable_codes.include?(code)
      [ 2, 0, chip.label.downcase, code ]
    else
      [ 3, 0, chip.label.downcase, code ]
    end
  end

  # Breadcrumb return path (audit, Fried): "Find a Room" should take you back
  # to YOUR search, not a bare reset. Same-origin referers pointing at the
  # index (with whatever query) qualify; anything else falls back clean.
  def find_a_room_return_path
    ref = URI.parse(request.referer.to_s)
    return find_a_room_path unless request.referer.present? &&
                                   ref.host == request.host && ref.path == find_a_room_path

    ref.request_uri
  rescue URI::InvalidURIError
    find_a_room_path
  end

  # Same override mechanism as characteristic_labels, for the vendor GROUP
  # names the More-filters panel uses as fieldset legends.
  def characteristic_group_name(group)
    I18n.t("rooms.characteristic_group_overrides.#{group.name}", default: group.name)
  end

  def promoted_filter_entries(filter_groups)
    by_code = filter_groups.flat_map(&:entries).index_by(&:short_code)
    PROMOTED_FILTER_CODES.filter_map do |code|
      members = RoomSearch::MERGED_CHARACTERISTICS[code]
      next by_code[code] unless members

      # A merged token earns its chip only when a member code exists in the
      # data — same present-in-data rule plain promoted codes get for free.
      merged_filter_entry(code) if members.any? { |member| by_code.key?(member) }
    end
  end

  # [group, remaining_entries] pairs for the More-filters panel; groups whose
  # entries were all promoted drop out entirely. Merged-token member codes
  # never render their own checkboxes: a non-promoted token substitutes ONE
  # synthetic entry into the first group holding a member (post-regroup
  # they're all in the same question group anyway); promoted tokens' members
  # simply drop, like any promoted code. Groups then follow the locale's
  # question-group order (rooms.filters.group_order) — the builder's
  # alphabetical sort is presentation-agnostic; the order is a product call.
  def panel_filter_groups(filter_groups)
    dropped  = PROMOTED_FILTER_CODES.to_set | RoomSearch::MERGED_CHARACTERISTICS.values.flatten
    injected = Set.new
    groups = filter_groups.filter_map do |group|
      entries = group.entries.reject { |entry| dropped.include?(entry.short_code) }
      RoomSearch::MERGED_CHARACTERISTICS.except(*PROMOTED_FILTER_CODES).each do |token, members|
        next if injected.include?(token) || (group.entries.map(&:short_code) & members).none?

        entries << merged_filter_entry(token)
        injected << token
      end
      [ group, entries.sort_by { |entry| entry.label.downcase } ] if entries.any?
    end
    order = Array(I18n.t("rooms.filters.group_order", default: [])).map(&:to_s)
    groups.sort_by.with_index { |(group, _), index| [ order.index(group.name) || order.size, index ] }
  end

  # Synthetic panel/chip entry for a merged token: no vendor row backs it, so
  # the label comes from the locale override map and the tooltip description
  # from rooms.filters.merged_descriptions.
  def merged_filter_entry(token)
    CharacteristicFilterGroups::Entry.new(
      short_code: token,
      label: characteristic_labels.fetch(token, token),
      long_description: t("rooms.filters.merged_descriptions.#{token}", default: nil)
    )
  end

  # How many applied filters live behind the More-filters disclosure —
  # panel-only characteristics plus unit and max capacity. Feeds the
  # summary's applied-count badge and the open-on-load rule below.
  def panel_filter_count(filter_params)
    # Only the characteristic pills still live inside the More-filters panel;
    # School/College (unit_id) and the capacity range moved up to the
    # always-visible filters (2026-07-16), so they no longer count toward this
    # disclosure's applied badge. Promoted pills are counted above the fold too.
    (Array(filter_params[:characteristics]) - PROMOTED_FILTER_CODES).size
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

    add.call(t("rooms.index.summary.saved"), base.except(:saved)) if base[:saved].present?
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
      # Bare characteristic label as the chip text: the chip IS an applied
      # filter, so a repeated "Filters:" prefix on each was pure noise
      # (2026-07-17 panel). Field-typed chips (Search:/Capacity:/…) keep their
      # prefix — it names the field. The sr-only RoomSearch#summary sentence is
      # unaffected (it still reads "Filters: …" for reading-order clarity).
      add.call(characteristic_labels.fetch(code, code),
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
end
