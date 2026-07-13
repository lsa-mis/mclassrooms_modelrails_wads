# frozen_string_literal: true

# View-model for the room detail page (Phase 4 Task 2, Brief §5.3): chips,
# data-driven feature grouping (D12), capacity/share text, and the room-show
# JSON payload Task 3's JSON variant renders via `render json: @presenter.as_json`.
#
# Grouping is data-driven by `CharacteristicDisplayRule#category_override`
# rather than hardcoded per-characteristic logic — the phase-1 seeds populate
# FEATURE_CATEGORIES' four buckets; `team_learning: true` rules form the TBL
# cluster regardless of category (mirrors `CharacteristicFilterGroups`'
# team_learning-overrides-category rule from phase 3 Task 3).
class RoomPresenter
  Chip = Data.define(:short_code, :label, :description, :icon_name, :team_learning)

  # Taxonomy phase 2 (2026-07-12): the buckets are the same question-group
  # vocabulary the Find-a-Room panel groups by — category_override holds the
  # display-ready group name, so one data lever drives both pages. Anything
  # un-overridden (or carrying a value outside this vocabulary) lands in
  # #other_features rather than silently dropping.
  FEATURE_CATEGORIES = {
    seats_layout: "Seats & layout",
    write_on: "Write on",
    show_present: "Show & present",
    recorded_accessible: "Recorded & accessible"
  }.freeze
  OTHER_CATEGORY = "other_features"

  # ADAPTATION: the phase-4 plan names `:sparkles` as the fallback icon, but
  # no `sparkles.svg` ships in this checkout's icon catalog
  # (app/assets/icons/{outline,solid}/ — 28 Heroicons, sparkles isn't among
  # them; `IconRegistry.exists?(:sparkles)` is false here). `IconHelper#icon`
  # calls `IconRegistry.find` directly, which raises `IconRegistry::NotFound`
  # for an unregistered name, so shipping `:sparkles` would only surface as a
  # 500 once Task 3/5 renders a chip that fell back. `:check_circle` is a
  # generic "feature present" icon confirmed to exist in this catalog — swap
  # back to `:sparkles` if that asset is ever added to app/assets/icons. The
  # spec asserts `IconRegistry.exists?(FALLBACK_ICON)` (not the literal
  # `:sparkles`) so this guard can't silently regress if the constant changes.
  FALLBACK_ICON = :check_circle

  def initialize(room, url: nil, rules: CharacteristicDisplayRule.all.index_by(&:short_code))
    @room = room
    @url = url
    @rules = rules
  end

  attr_reader :room

  def capacity_line
    I18n.t("rooms.show.capacity", students: room.instructional_seat_count, ada: room.ada_seat_count.to_i)
  end

  def chips
    @chips ||= room.room_characteristics.sort_by(&:short_code).map { |c| build_chip(c) }
  end

  FEATURE_CATEGORIES.each do |method_name, category|
    define_method(method_name) { grouped_chips.fetch(category, []) }
  end

  def team_based_learning
    chips.select(&:team_learning)
  end

  # The catch-all EXCLUDES team_learning chips: a categorized TBL chip shows
  # in its question group AND the TBL cluster (pinned by spec), but an
  # un-overridden one already has a home in the cluster — echoing it under
  # "More details" would be pure noise.
  def other_features
    grouped_chips.fetch(OTHER_CATEGORY, []).reject(&:team_learning)
  end

  # One line: display name — full address — capacity — canonical URL (Brief
  # §5.3). ADAPTATION: the plan's reference code reads
  # `room.building.address_line`, which does not exist on Building — the real
  # method (app/models/building.rb:37) is `#full_address` (joins
  # address/city/"state zip"/country, blank-compacted).
  def share_text
    [ room.display_name, room.building.full_address, capacity_line, @url ].compact_blank.join(" — ")
  end

  # Room-show JSON (Brief §5.3), consumed verbatim by Task 3's JSON variant
  # (`render json: @presenter.as_json`).
  def as_json(*)
    {
      id: room.id,
      rmrecnbr: room.rmrecnbr,
      facility_code: room.facility_code,
      display_name: room.display_name,
      nickname: room.nickname,
      building: {
        id: room.building.id,
        name: room.building.name,
        abbreviation: room.building.abbreviation
      },
      floor_label: room.floor&.label,
      room_number: room.room_number,
      room_type: room.room_type,
      square_feet: room.square_feet,
      instructional_seat_count: room.instructional_seat_count,
      ada_seat_count: room.ada_seat_count,
      department: department_json,
      characteristics: chips.map(&:short_code),
      media: media_json,
      contacts: contacts_json,
      url: @url
    }
  end

  private

  def grouped_chips
    @grouped_chips ||= chips.group_by { |chip| category_for(chip.short_code) }
  end

  def category_for(short_code)
    override = @rules[short_code]&.category_override.presence
    FEATURE_CATEGORIES.value?(override) ? override : OTHER_CATEGORY
  end

  # The visible chip label is the parsed VALUE ("Document Camera", never
  # "Equipment: Document Camera" — the category is the grouping heading, not
  # part of the name), with the same product-level locale overrides the
  # Find-a-Room page applies (rooms.characteristic_label_overrides).
  def chip_label(characteristic)
    overrides = I18n.t("rooms.characteristic_label_overrides", default: {}).stringify_keys
    overrides.fetch(characteristic.short_code) do
      value = characteristic.description.to_s.split(":", 2).last.to_s.strip
      value.presence || characteristic.short_code
    end
  end

  def build_chip(characteristic)
    rule = @rules[characteristic.short_code]
    icon = rule&.icon_key
    icon = FALLBACK_ICON unless icon.present? && IconRegistry.exists?(icon)
    Chip.new(
      short_code: characteristic.short_code,
      label: chip_label(characteristic),
      description: characteristic.long_description,
      icon_name: icon.to_sym,
      team_learning: rule&.team_learning? || false
    )
  end

  # RESOLVED AMBIGUITY: the JSON contract wants four department fields, but
  # `Unit` (app/models/unit.rb) has only `id`, `department_group` (the DeptGrp
  # CODE), `description` (the DeptGrpDescr) and `#display_name` (the
  # UnitDisplayName-overridden label). Mapping: `description` gets the
  # human-facing `#display_name`; `group`/`group_description` get the two raw
  # Unit columns. nil (not an empty hash) when the room has no unit.
  def department_json
    return nil unless room.unit

    {
      id: room.unit.id,
      description: room.unit.display_name,
      group: room.unit.department_group,
      group_description: room.unit.description
    }
  end

  # nil (not an empty hash) when the room has no contact record.
  def contacts_json
    contact = room.room_contact
    return nil unless contact

    {
      scheduling_name: contact.scheduling_name,
      scheduling_email: contact.scheduling_email,
      scheduling_phone: contact.scheduling_phone,
      scheduling_detail_url: contact.scheduling_detail_url,
      scheduling_usage_guidelines_url: contact.scheduling_usage_guidelines_url,
      support_department_id: contact.support_department_id,
      support_department_description: contact.support_department_description,
      support_email: contact.support_email,
      support_phone: contact.support_phone,
      support_url: contact.support_url
    }
  end

  def media_json
    {
      photo_url: blob_url(room.photo),
      thumbnail_url: thumbnail_url,
      panorama_url: blob_url(room.panorama),
      seating_chart_url: blob_url(room.seating_chart),
      gallery_urls: room.gallery_images.ordered.filter_map { |image| blob_url(image.image) }
    }
  end

  # 150×150 WebP variant of the room photo (D9). `rails_representation_url`
  # is the ActiveStorage route helper for a *variant*, as opposed to
  # `rails_blob_url` (used for the original blob elsewhere in this file) —
  # mirrors how phase-1/phase-3 views build thumbnails
  # (app/views/rooms/_room_row.html.erb, _building_card.html.erb:
  # `url_for(attachment.variant(resize_to_fill: [w, h]))`), just called
  # through the route helpers directly since this class has no view context.
  def thumbnail_url
    return nil unless room.photo.attached?

    url_helpers.rails_representation_url(room.photo.variant(resize_to_fill: [ 150, 150 ], format: :webp))
  end

  def blob_url(attachment)
    return nil unless attachment.attached?

    url_helpers.rails_blob_url(attachment)
  end

  def url_helpers
    Rails.application.routes.url_helpers
  end
end
