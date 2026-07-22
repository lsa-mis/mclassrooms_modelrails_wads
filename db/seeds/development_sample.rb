# DEV-ONLY sample data for the MClassrooms shared workspace (Rails.env
# development? only — see the guard in `seed!` below, mirrored in
# db/seeds.rb and lib/tasks/dev.rake so both entry points are self-guarding).
#
# Populates the shared workspace (D1 — TenancyConfig.shared?) with a small,
# realistic-looking Building/Floor/Unit/Room/RoomCharacteristic/
# EditorAssignment/Note/Announcement dataset so Find a Room, room show
# pages, and the admin consoles are actually browsable locally instead of
# empty. This is throwaway sample data, not production reference data —
# contrast with db/seeds/reference_data.yml (ReferenceData.seed!), which
# ships real cutover-bound display rules/unit names/sync-scope rules.
#
# Idempotent: every write is a `find_or_create_by!` keyed on the model's
# natural key (or, for Room/Building, the same workspace+name/room_number
# shape the rest of this codebase already treats as the natural identity —
# see ReferenceData's own natural-key comment). Re-running `rails db:seed`
# or `rails dev:sample_data` leaves row counts unchanged.
module DevelopmentSampleData
  module_function

  UNITS = [
    { department_group: "MATH", description: "Department of Mathematics", display_name: "Mathematics" },
    { department_group: "PHYSICS", description: "Department of Physics", display_name: "Physics" },
    { department_group: "ENGLISH", description: "Department of English Language & Literature",
      display_name: "English Language & Literature" },
    { department_group: "CHEM", description: "Department of Chemistry", display_name: "Chemistry" }
  ].freeze

  # short_code is already normalization-stable (lowercase alnum) so it
  # round-trips unchanged through CharacteristicDisplayRule's
  # before_validation normalize (CodeNormalizer) — see app/lib/code_normalizer.rb.
  CHARACTERISTICS = [
    { code: "PROJ", short_code: "proj", description: "Audio/Visual: Projector",
      long_description: "Ceiling-mounted digital projector with HDMI and wireless casting support.",
      icon_key: "camera" },
    { code: "WHTBRD", short_code: "whtbrd", description: "Audio/Visual: Whiteboard",
      long_description: "Full dry-erase whiteboard.", icon_key: "pencil" },
    { code: "ADA", short_code: "ada", description: "Accessibility: ADA Accessible",
      long_description: "Room meets ADA accessibility guidelines, including accessible seating and door clearance.",
      icon_key: "user_circle" },
    { code: "MOVSEAT", short_code: "movseat", description: "Seating: Movable Tablet-Arm Chairs",
      long_description: "Movable tablet-arm chairs that can be reconfigured for group work.",
      icon_key: "arrow_path", team_learning: true },
    { code: "COMPLAB", short_code: "complab", description: "Technology: Student Computer Workstations",
      long_description: "Fixed student computer workstations for hands-on instruction.",
      icon_key: "computer_desktop" },
    { code: "VIDCONF", short_code: "vidconf", description: "Technology: Video Conferencing",
      long_description: "Room is equipped for two-way video conferencing.", icon_key: "globe_alt" }
  ].freeze

  # One entry per building: address, department Unit it's primarily used by,
  # floor labels to create, and the rooms on each floor. Room numbers,
  # capacities, and characteristic mixes are hand-picked (not Faker) so the
  # dataset reads as a plausible slice of a real campus facility inventory.
  BUILDINGS = [
    {
      name: "Mason Hall", bldrecnbr: "MC-BLD-0001", abbreviation: "MH",
      address: "419 S State St", city: "Ann Arbor", state: "MI", zip: "48109", country: "USA",
      unit: "ENGLISH", floors: %w[1 2 3],
      rooms: [
        { room_number: "1010", floor: "1", capacity: 40, characteristics: %w[proj whtbrd] },
        { room_number: "1030", floor: "1", capacity: 120, nickname: "Lecture Hall",
          characteristics: %w[proj vidconf ada] },
        { room_number: "1200", floor: "1", capacity: 35, characteristics: %w[proj], hidden: true },
        { room_number: "2306", floor: "2", capacity: 24, characteristics: %w[whtbrd movseat] },
        { room_number: "2315", floor: "2", capacity: 18, characteristics: %w[ada] },
        { room_number: "3100", floor: "3", capacity: 300, nickname: "Auditorium",
          characteristics: %w[proj vidconf] },
        { room_number: "3210", floor: "3", capacity: 45, characteristics: %w[proj whtbrd ada] }
      ]
    },
    {
      name: "Angell Hall", bldrecnbr: "MC-BLD-0002", abbreviation: "AH",
      address: "435 S State St", city: "Ann Arbor", state: "MI", zip: "48109", country: "USA",
      unit: "ENGLISH", floors: %w[G 1 2],
      rooms: [
        { room_number: "G115", floor: "G", capacity: 350, nickname: "Auditorium A",
          characteristics: %w[proj vidconf] },
        { room_number: "G220", floor: "G", capacity: 200, nickname: "Auditorium B",
          characteristics: %w[proj vidconf ada] },
        { room_number: "1210", floor: "1", capacity: 60, characteristics: %w[proj whtbrd] },
        { room_number: "1420", floor: "1", capacity: 30, characteristics: %w[movseat whtbrd] },
        { room_number: "2202", floor: "2", capacity: 20, characteristics: %w[ada] },
        { room_number: "2340", floor: "2", capacity: 75, characteristics: %w[proj] }
      ]
    },
    {
      name: "East Hall", bldrecnbr: "MC-BLD-0003", abbreviation: "EH",
      address: "530 Church St", city: "Ann Arbor", state: "MI", zip: "48109", country: "USA",
      unit: "MATH", floors: %w[1 2 3 4],
      rooms: [
        { room_number: "1324", floor: "1", capacity: 35, characteristics: %w[proj whtbrd] },
        { room_number: "1360", floor: "1", capacity: 90, characteristics: %w[proj ada] },
        { room_number: "2843", floor: "2", capacity: 24, characteristics: %w[whtbrd] },
        { room_number: "2866", floor: "2", capacity: 16, nickname: "Seminar Room",
          characteristics: %w[movseat] },
        { room_number: "3088", floor: "3", capacity: 45, characteristics: %w[proj whtbrd movseat] },
        { room_number: "4088", floor: "4", capacity: 20, characteristics: %w[ada] }
      ]
    },
    {
      name: "Randall Laboratory", bldrecnbr: "MC-BLD-0004", abbreviation: "RL",
      address: "450 Church St", city: "Ann Arbor", state: "MI", zip: "48109", country: "USA",
      unit: "PHYSICS", floors: %w[1 2 3],
      rooms: [
        { room_number: "1049", floor: "1", capacity: 150, nickname: "Lecture Hall",
          characteristics: %w[proj vidconf] },
        { room_number: "1120", floor: "1", capacity: 40, characteristics: %w[proj whtbrd] },
        { room_number: "2054", floor: "2", capacity: 24, characteristics: %w[movseat] },
        { room_number: "2064", floor: "2", capacity: 12, nickname: "Seminar Room",
          characteristics: %w[whtbrd] },
        { room_number: "3038", floor: "3", capacity: 35, characteristics: %w[proj ada] },
        { room_number: "3401", floor: "3", capacity: 300, nickname: "Auditorium",
          characteristics: %w[proj vidconf ada] }
      ]
    },
    {
      name: "Chemistry Building", bldrecnbr: "MC-BLD-0005", abbreviation: "CB",
      address: "930 N University Ave", city: "Ann Arbor", state: "MI", zip: "48109", country: "USA",
      unit: "CHEM", floors: %w[1 2 3],
      rooms: [
        { room_number: "1210", floor: "1", capacity: 200, nickname: "Lecture Hall",
          characteristics: %w[proj vidconf] },
        { room_number: "1300", floor: "1", capacity: 24, nickname: "Computer Lab",
          characteristics: %w[complab proj] },
        { room_number: "2306", floor: "2", capacity: 18, nickname: "Computer Lab",
          characteristics: %w[complab] },
        { room_number: "2400", floor: "2", capacity: 45, characteristics: %w[proj whtbrd] },
        { room_number: "3216", floor: "3", capacity: 10, nickname: "Seminar Room",
          characteristics: %w[ada] },
        { room_number: "3340", floor: "3", capacity: 60, characteristics: %w[proj movseat] }
      ]
    }
  ].freeze

  ANNOUNCEMENTS = {
    "home_page" => "Welcome to the University of Michigan Classroom Directory. Search buildings and " \
      "rooms, check capacities and features, and find the right space for your class.",
    "find_a_room_page" => "Use the filters below to narrow rooms by building, capacity, and features " \
      "like projectors, whiteboards, and ADA accessibility.",
    "about_page" => "MClassrooms is a directory of University of Michigan classrooms, maintained by " \
      "the Registrar's Office and campus facilities teams to help instructors and students find the " \
      "right room."
  }.freeze

  def seed!
    return unless Rails.env.development?
    return unless TenancyConfig.shared?

    workspace = TenancyConfig.shared_workspace
    return unless workspace

    units = seed_units(workspace)
    seed_characteristic_display_rules(workspace)
    buildings = seed_buildings(workspace)
    seed_floors_and_rooms(workspace, buildings, units)
    seed_editor_assignments(workspace, units)
    seed_notes(workspace, buildings)
    seed_announcements(workspace)

    Rails.logger.info(
      "[dev-seed] MClassrooms sample data ready in workspace '#{workspace.slug}': " \
      "#{Unit.where(workspace: workspace).count} units, " \
      "#{Building.where(workspace: workspace).count} buildings, " \
      "#{Room.where(workspace: workspace).count} rooms."
    )
  end

  def seed_units(workspace)
    UNITS.each_with_object({}) do |attrs, memo|
      unit = Unit.find_or_create_by!(workspace: workspace, department_group: attrs[:department_group]) do |u|
        u.description = attrs[:description]
      end
      UnitDisplayName.find_or_create_by!(workspace: workspace, department_group: attrs[:department_group]) do |udn|
        udn.display_name = attrs[:display_name]
      end
      memo[attrs[:department_group]] = unit
    end
  end

  def seed_characteristic_display_rules(workspace)
    CHARACTERISTICS.each do |attrs|
      CharacteristicDisplayRule.find_or_create_by!(workspace: workspace, short_code: attrs[:short_code]) do |rule|
        rule.icon_key = attrs[:icon_key]
        rule.filterable = true
        rule.team_learning = attrs.fetch(:team_learning, false)
      end
    end
  end

  def seed_buildings(workspace)
    BUILDINGS.each_with_object({}) do |attrs, memo|
      building = Building.find_or_create_by!(workspace: workspace, name: attrs[:name]) do |b|
        b.bldrecnbr = attrs[:bldrecnbr]
        b.abbreviation = attrs[:abbreviation]
        b.address = attrs[:address]
        b.city = attrs[:city]
        b.state = attrs[:state]
        b.zip = attrs[:zip]
        b.country = attrs[:country]
        b.in_feed = true
      end
      memo[attrs[:name]] = building
    end
  end

  def seed_floors_and_rooms(workspace, buildings, units)
    rmrecnbr_seq = 0

    BUILDINGS.each do |building_data|
      building = buildings.fetch(building_data[:name])
      unit = units.fetch(building_data[:unit])
      floors_by_label = building_data[:floors].index_with do |label|
        Floor.find_or_create_by!(building: building, workspace: workspace, label: label)
      end

      building_data[:rooms].each do |room_data|
        rmrecnbr_seq += 1
        seed_room(workspace, building, unit, floors_by_label.fetch(room_data[:floor]), room_data, rmrecnbr_seq)
      end
    end
  end

  def seed_room(workspace, building, unit, floor, room_data, seq)
    room = Room.find_or_create_by!(workspace: workspace, building: building, room_number: room_data[:room_number]) do |r|
      r.rmrecnbr = format("MC-RM-%04d", seq)
      r.facility_code = "#{building.abbreviation}#{room_data[:room_number]}"
      r.building_name = building.name
      r.floor = floor
      r.unit = unit
      r.room_type = "Classroom"
      r.instructional_seat_count = room_data[:capacity]
      r.nickname = room_data[:nickname]
      r.in_feed = true
      if room_data[:hidden]
        r.hidden_at = Time.current
        r.hidden_by = workspace.owner
      end
    end

    seed_room_characteristics(workspace, room, room_data[:characteristics])
  end

  def seed_room_characteristics(workspace, room, short_codes)
    Array(short_codes).each do |short_code|
      attrs = CHARACTERISTICS.find { |c| c[:short_code] == short_code } or
        raise ArgumentError, "unknown characteristic short_code #{short_code.inspect}"

      room.room_characteristics.find_or_create_by!(code: attrs[:code]) do |rc|
        rc.workspace = workspace
        rc.short_code = attrs[:short_code]
        rc.description = attrs[:description]
        rc.long_description = attrs[:long_description]
        rc.status = "Active"
      end
    end
  end

  # hd@humbledaisy.com edits two units' rooms — demoes the unit-editor role
  # without needing a third dev user. Reused if it already exists (it's
  # created earlier in db/seeds.rb's own bootstrap flow); the block only
  # fires if this seed is ever run before that user exists.
  def seed_editor_assignments(workspace, units)
    editor = User.find_or_create_by!(email_address: "hd@humbledaisy.com") do |u|
      u.first_name = "HD"
      u.last_name = "Editor"
      password = SecureRandom.urlsafe_base64(24)
      u.password = password
      u.password_confirmation = password
    end

    %w[ENGLISH PHYSICS].each do |department_group|
      EditorAssignment.find_or_create_by!(workspace: workspace, user: editor, unit: units.fetch(department_group))
    end
  end

  def seed_notes(workspace, buildings)
    author = buildings.values.first.workspace.owner

    room_for = ->(building_name, room_number) {
      Room.find_by!(workspace: workspace, building: buildings.fetch(building_name), room_number: room_number)
    }

    create_note(workspace, room_for.call("Mason Hall", "1030"), author, alert: false,
      body: "Projector bulb replaced Fall 2025 — report any dimming issues to Facilities.")
    create_note(workspace, room_for.call("East Hall", "2866"), author, alert: false,
      body: "Room reconfigured for small-group seminar use; movable chairs added Winter 2026.")
    create_note(workspace, room_for.call("Randall Laboratory", "3401"), author, alert: true,
      body: "HVAC making unusual noise — Facilities ticket #4521 filed; avoid scheduling until resolved.")
  end

  def create_note(workspace, room, author, alert:, body:)
    Note.find_or_create_by!(workspace: workspace, notable: room, author: author, alert: alert) do |note|
      note.body = body
    end
  end

  def seed_announcements(workspace)
    ANNOUNCEMENTS.each do |slot, body|
      Announcement.find_or_create_by!(slot: slot) do |a|
        a.workspace = workspace
        a.body = body
      end
    end
  end
end
