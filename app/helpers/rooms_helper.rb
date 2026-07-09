# MiClassrooms Phase 3 Task 5 (Brief §5.2): Find a Room row helpers.
module RoomsHelper
  # short_code => icon_key for characteristics that have an icon configured.
  # Memoized per request (a plain ivar, not Rails.cache — CharacteristicDisplayRule
  # rows rarely change and this only needs to survive one index render), so the
  # N-row results list issues exactly one query for this lookup instead of one
  # per row.
  def characteristic_icon_keys
    @characteristic_icon_keys ||=
      CharacteristicDisplayRule.where.not(icon_key: [ nil, "" ]).pluck(:short_code, :icon_key).to_h
  end

  # Icon chips for a room's key characteristics (Brief §5.2 row icons): only
  # characteristics with a configured icon_key get a chip. `IconRegistry.exists?`
  # guards a stale/typo'd icon_key (e.g. an admin renamed an icon file) so a
  # display-rule data issue degrades to "no chip" rather than a 500 on this
  # index page. `room.room_characteristics` reads the RoomSearch#results
  # preload — no query here.
  def room_characteristic_icons(room)
    room.room_characteristics.filter_map do |rc|
      icon_key = characteristic_icon_keys[rc.short_code]
      next unless icon_key.present? && IconRegistry.exists?(icon_key)

      [ icon_key, CharacteristicFilterGroups.label_for(rc.short_code) ]
    end
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
    room.room_characteristics.map { |rc| CharacteristicFilterGroups.label_for(rc.short_code) }.sort
  end

  # Building-photo placeholder initials (Brief §5.2 building card): first
  # letter of up to the first two words — "Mason Hall" -> "MH", "Angell" ->
  # "A". Presentational only, so it lives here rather than as a model method.
  def building_initials(building)
    building.name.to_s.split.first(2).filter_map { |word| word[0] }.join.upcase
  end
end
