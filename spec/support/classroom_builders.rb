# Shared classroom-fixture builder (Phase 3 Tasks 2/4/8). Include for
# type: :system and lib/request specs that need realistic Find-a-Room rooms.
module ClassroomBuilders
  def classroom(building, number, seats, codes: [], floor: nil)
    create(:room, building:, room_number: number, room_type: "Classroom",
           facility_code: "#{building.name[0, 3].upcase}#{number}",
           instructional_seat_count: seats, floor:).tap do |room|
      # Normalized here to mirror production: the characteristics sync (phase 2)
      # writes RoomCharacteristic.short_code through CodeNormalizer, so a raw
      # human-friendly code like "LectureCap" lands as "lecturecap" — matching
      # what RoomSearch's characteristics filter normalizes an incoming param to.
      codes.each { |c| create(:room_characteristic, room:, short_code: CodeNormalizer.normalize(c), description: "Technology: #{c}") }
    end
  end
end
