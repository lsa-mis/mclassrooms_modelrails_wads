# MiClassrooms Phase 3 Task 4 (Brief §5.2): Find a Room JSON. Every field
# read here comes off an already-preloaded association (RoomSearch#results —
# see lib/bullet_safelists.rb) so this stays N+1-free without its own includes.
json.rooms @rooms do |room|
  json.id room.id
  json.rmrecnbr room.rmrecnbr
  json.facility_code room.facility_code
  json.display_name room.display_name
  json.building room.building.display_name
  json.capacity room.instructional_seat_count
  json.ada_capacity room.ada_seat_count
  json.characteristics room.room_characteristics.map(&:short_code)
  json.floor room.floor&.label
end

json.pagination do
  json.page @pagy.page
  json.pages @pagy.pages
  json.count @pagy.count
  json.per @search.per_page
end
