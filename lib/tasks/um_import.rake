# frozen_string_literal: true

# DEV-ONLY data importer: pulls REAL University of Michigan classroom data
# from the live U-M API gateway into MiClassrooms' Building/Floor/Unit/Room/
# RoomCharacteristic/CharacteristicDisplayRule models, so the app can be
# validated against representative real-world data instead of hand-authored
# fixtures (contrast db/seeds/development_sample.rb).
#
# Why this exists instead of `rails sync:run` (Sync::RunPipeline,
# app/lib/sync/*): that pipeline's endpoints/params/field names were built
# against spec/support/um_api_stubs.rb's STUB fixtures and don't match the
# real gateway (verified interactively — e.g. the real departments endpoint
# is `/bf/Department/v2/DeptData`, not Sync::UpdateRooms's guessed
# `/bf/Buildings/v2/Departments`; the real classroom-facility crosswalk has
# no `RmRecNbr` at its top level at all). This task is a separate,
# production-proven recipe (ported from the legacy MiClassrooms app,
# re-verified against the live gateway) that talks to the SAME
# `UmApi::Client` — the HTTP/auth/pagination/rate-limit layer is fine, only
# Sync::*'s endpoint paths and field names are wrong — using the real paths
# and real field names below. It does NOT touch `Sync::BasePhase`,
# `SyncRun`, `SyncPhase`, or `SyncScopeRule`.
#
# Idempotent: every write is a `find_or_initialize_by`/`find_or_create_by!`
# on a natural key (bldrecnbr, rmrecnbr, department_group, characteristic
# short_code, ...). Re-running leaves row counts stable — see the report at
# .superpowers/sdd/um-import-report.md for a verified before/after count.
#
# Scope: a building is imported if its BuildingCampusCode is in
# `campus_allow` OR its BuildingRecordNumber is in `building_allow`, and it
# is NOT in `building_exclude`. Configurable via ENV (UM_IMPORT_CAMPUS_ALLOW
# / UM_IMPORT_BUILDING_ALLOW / UM_IMPORT_BUILDING_EXCLUDE, comma-separated)
# or a `campus_allow` rake arg — e.g. `rails "um:import[100]"` switches to
# the full Central Campus. Defaults to the 7 named academic buildings used
# for fast local validation.
namespace :um do
  desc "Import real U-M classroom data from the live gateway into the shared DEV workspace (see UmImport)"
  task :import, [ :campus_allow ] => :environment do |_t, args|
    UmImport.run!(campus_allow_arg: args[:campus_allow])
  end
end

# Namespaced outside app/ (throwaway dev tooling, not application code) so
# nothing here is autoloaded/eager-loaded in test/production.
module UmImport
  BASE_URL = "https://gw.api.it.umich.edu/um"
  TOKEN_URL = "#{BASE_URL}/oauth2/token"

  BUILDING_INFO_PATH = "/bf/Buildings/v2/BuildingInfo"
  ROOM_INFO_PATH = "/bf/Buildings/v2/RoomInfo"
  DEPT_DATA_PATH = "/bf/Department/v2/DeptData"
  CLASSROOMS_PATH = "/aa/ClassroomList/v2/Classrooms"

  DEFAULT_BUILDING_ALLOW = %w[1000440 1000234 1000204 1000333 1005224 1005059 1005347].freeze
  DEFAULT_BUILDING_EXCLUDE = %w[1000890].freeze
  DEFAULT_CAMPUS_ALLOW = [].freeze

  PAGE_SIZE = 1000

  # short_code/description keyword => IconRegistry icon name, checked in
  # order (first match wins). IconRegistry's set (app/assets/icons) is
  # generic — no "whiteboard"/"wifi"/"table" icon exists — so this is a
  # best-effort semantic grouping, not a precise catalog. Every candidate is
  # still verified against IconRegistry.exists? before use (falls back to
  # FALLBACK_ICON otherwise), so a bad guess here can never write an invalid
  # icon_key — unlike db/seeds/reference_data.yml's "computer"/
  # "video-camera"/"table"/"whiteboard", none of which actually exist.
  ICON_RULES = [
    [ /board|chalk/i, "pencil" ],
    [ /computer|\bpc\b|podium/i, "computer_desktop" ],
    [ /project|screen|document camera|dvd|blu-?ray|\bvcr\b/i, "camera" ],
    [ /video conf|lecture cap|interactive/i, "globe_alt" ],
    [ /wheelchair|accessib/i, "user_circle" ],
    [ /seat|table|chair/i, "user_group" ],
    [ /sound|voice|amplif|listen/i, "bell" ],
    [ /power|outlet|ethernet|network/i, "cog" ],
    [ /floor|carpet|tile|wood|window|blackout|platform|stage|tier/i, "home" ]
  ].freeze
  FALLBACK_ICON = "information_circle"

  module_function

  def run!(campus_allow_arg: nil)
    abort "um:import only runs in development (current env: #{Rails.env})" unless Rails.env.development?
    unless TenancyConfig.shared?
      abort "um:import requires TENANCY_ONBOARDING=shared (current: #{TenancyConfig.onboarding.inspect})"
    end
    workspace = TenancyConfig.shared_workspace
    abort "um:import: no shared workspace found" unless workspace

    bridge_credentials!
    Current.workspace = workspace

    client = UmApi::Client.new
    scope = resolve_scope(campus_allow_arg)
    puts "[um:import] scope: campus_allow=#{scope[:campus_allow].inspect} " \
         "building_allow=#{scope[:building_allow].inspect} building_exclude=#{scope[:building_exclude].inspect}"

    buildings_by_id = import_buildings(client, scope)
    puts "[um:import] buildings in scope: #{buildings_by_id.size}"

    dept_index = load_department_index(client)
    puts "[um:import] department rows loaded: #{dept_index.size}"

    room_stats = import_rooms(client, buildings_by_id, dept_index)
    puts "[um:import] rooms: created=#{room_stats[:created]} updated=#{room_stats[:updated]} " \
         "total_classrooms=#{room_stats[:rooms].size}"

    char_stats = import_characteristics(client, buildings_by_id, room_stats[:rooms])
    puts "[um:import] characteristics: facility_calls=#{char_stats[:facility_calls]} " \
         "rooms_matched_to_facility=#{char_stats[:matched_rooms]}/#{room_stats[:rooms].size} " \
         "characteristic_rows=#{char_stats[:characteristic_rows]} " \
         "display_rules_created=#{char_stats[:display_rules_created]}"

    print_summary(workspace, client)
  end

  # === Credential bridge (in-process only — see task-level comment) ===

  def bridge_credentials!
    ENV["UM_API_TOKEN_URL"] = TOKEN_URL
    ENV["UM_API_BASE_URL"] = BASE_URL
    credentials = Rails.application.credentials.um_api
    ENV["UM_API_CLIENT_ID"] = credentials.buildings_client_id.to_s
    ENV["UM_API_CLIENT_SECRET"] = credentials.buildings_client_secret.to_s
  end

  # === Scope resolution ===

  def resolve_scope(campus_allow_arg)
    campus_allow = campus_allow_arg.present? ? split_csv(campus_allow_arg) : env_list("UM_IMPORT_CAMPUS_ALLOW", DEFAULT_CAMPUS_ALLOW)
    {
      campus_allow: campus_allow,
      building_allow: env_list("UM_IMPORT_BUILDING_ALLOW", DEFAULT_BUILDING_ALLOW),
      building_exclude: env_list("UM_IMPORT_BUILDING_EXCLUDE", DEFAULT_BUILDING_EXCLUDE)
    }
  end

  def env_list(key, default)
    ENV.key?(key) ? split_csv(ENV[key]) : default
  end

  def split_csv(value)
    value.to_s.split(",").map(&:strip).compact_blank
  end

  def building_in_scope?(row, scope)
    bldrecnbr = row["BuildingRecordNumber"]
    return false if scope[:building_exclude].include?(bldrecnbr)

    scope[:campus_allow].include?(row["BuildingCampusCode"]) || scope[:building_allow].include?(bldrecnbr)
  end

  # === Gateway paging (real param names: $start_index / $count — the
  # `limit`-based `UmApi::Client#each_page` 400s against the live gateway,
  # so this walks pages manually via plain #get_json calls instead) ===

  def paged_fetch(client, path, scope:, array_path:, extra_params: {})
    rows = []
    start_index = 0

    loop do
      page = client.rate_limiter.backoff_429 do
        body = client.get_json(path, params: extra_params.merge("$start_index" => start_index, "$count" => PAGE_SIZE), scope: scope)
        array_path.reduce(body) { |acc, key| acc.is_a?(Hash) ? acc[key] : nil } || []
      end
      rows.concat(page)
      break if page.size < PAGE_SIZE

      start_index += PAGE_SIZE
    end

    rows
  end

  # === Buildings + Campuses ===

  def import_buildings(client, scope)
    rows = paged_fetch(client, BUILDING_INFO_PATH, scope: "buildings", array_path: [ "ListOfBldgs", "Buildings" ])
    in_scope = rows.select { |row| building_in_scope?(row, scope) }
    campuses_by_code = import_campuses(in_scope)

    in_scope.each_with_object({}) do |row, memo|
      memo[row["BuildingRecordNumber"]] = upsert_building(row, campuses_by_code)
    end
  end

  def import_campuses(rows)
    pairs = rows.filter_map { |row|
      code = row["BuildingCampusCode"]
      [ code, row["BuildingCampusDescription"] ] if code.present?
    }.uniq(&:first)

    pairs.each_with_object({}) do |(code, description), memo|
      campus = Campus.for_current_workspace.find_or_initialize_by(code: code)
      campus.description = description if campus.description != description
      campus.save!
      memo[code] = campus
    end
  end

  def upsert_building(row, campuses_by_code)
    building = Building.for_current_workspace.find_or_initialize_by(bldrecnbr: row["BuildingRecordNumber"])
    building.assign_attributes(
      name: row["BuildingLongDescription"],
      abbreviation: row["BuildingShortDescription"],
      address: building_address(row),
      city: row["BuildingCity"],
      state: row["BuildingState"],
      zip: row["BuildingPostal"],
      country: "USA",
      campus: campuses_by_code[row["BuildingCampusCode"]],
      in_feed: true
    )
    building.save!
    building
  end

  def building_address(row)
    [ row["BuildingStreetNumber"], row["BuildingStreetDirection"], row["BuildingStreetName"] ].compact_blank.join(" ")
  end

  # === Departments (=> Units) ===

  # One paged fetch, keyed by the department's own DeptDescription — the
  # exact string RoomInfo's per-room DepartmentName repeats — so every
  # room's lookup after this is an O(1) hash read, never a per-row gateway
  # call.
  def load_department_index(client)
    rows = paged_fetch(client, DEPT_DATA_PATH, scope: "department", array_path: [ "DepartmentList", "DeptData" ])
    rows.index_by { |row| row["DeptDescription"] }
  end

  def resolve_unit(dept_row)
    group_code = dept_row&.dig("DeptGroup").to_s.strip.presence
    return nil unless group_code

    group_description = dept_row["DeptGroupDescription"]
    unit = Unit.for_current_workspace.find_or_initialize_by(department_group: group_code)
    unit.description = group_description if unit.description != group_description
    unit.save!
    unit
  end

  # === Rooms (Classroom-typed only — see task-level comment) ===

  def import_rooms(client, buildings_by_id, dept_index)
    rooms = buildings_by_id.each_value.flat_map do |building|
      rows = paged_fetch(client, "#{ROOM_INFO_PATH}/#{building.bldrecnbr}", scope: "buildings", array_path: [ "ListOfRooms", "RoomData" ])
      rows.select { |row| row["RoomTypeDescription"] == "Classroom" }.map { |row| upsert_room(row, building, dept_index) }
    end

    # previously_new_record?/saved_changes? reflect each room's #save! call
    # inside upsert_room above (each room saves as it goes, so a later
    # failure never loses earlier rooms) — never a second save here.
    {
      created: rooms.count(&:previously_new_record?),
      updated: rooms.count { |r| !r.previously_new_record? && r.saved_changes? },
      rooms: rooms
    }
  end

  def upsert_room(row, building, dept_index)
    dept_row = dept_index[row["DepartmentName"]]
    unit = resolve_unit(dept_row)
    floor = Floor.for_current_workspace.find_or_create_by!(building: building, label: normalize_floor_label(row["FloorNumber"]))

    room = Room.for_current_workspace.find_or_initialize_by(rmrecnbr: row["RoomRecordNumber"])
    # facility_code is deliberately NOT assigned here: it is set by the
    # characteristics phase (import_characteristics) from the real
    # FacilityID crosswalk, and must never be reset to nil on a re-run that
    # only re-walks RoomInfo.
    room.assign_attributes(
      building: building,
      building_name: building.name,
      floor: floor,
      campus: building.campus,
      unit: unit,
      department_id: dept_row&.dig("DeptId"),
      department_description: dept_row&.dig("DeptDescription"),
      department_group: dept_row&.dig("DeptGroup"),
      department_group_description: dept_row&.dig("DeptGroupDescription"),
      room_number: row["RoomNumber"],
      room_type: row["RoomTypeDescription"],
      square_feet: row["RoomSquareFeet"],
      instructional_seat_count: row["RoomStationCount"],
      in_feed: true
    )
    room.save!
    room
  end

  # "01" -> "1", "0G" -> "G", "00" -> "0" — strips leading zeros but never
  # collapses a label to nothing, matching the "1"/"2"/"G" style
  # db/seeds/development_sample.rb already uses for hand-authored floors.
  def normalize_floor_label(raw)
    raw.to_s.strip.sub(/\A0+(?=.)/, "")
  end

  # === Characteristics (highest call-volume phase — see task-level comment
  # on resilience: a failure anywhere in here must not lose the
  # buildings/rooms/units already committed above) ===

  def import_characteristics(client, buildings_by_id, rooms)
    stats = { facility_calls: 0, matched_rooms: 0, characteristic_rows: 0, display_rules_created: 0 }
    rooms_by_rmrecnbr = rooms.index_by(&:rmrecnbr)

    # The gateway's own BuildingID query-param filtering on this endpoint is
    # unverified against live credentials, so — same caution as
    # UmApi::Client#each_page's PAGE_SIZE_PARAM guess — this fetches the
    # FULL facility crosswalk ONCE (paged; ~1600 rows campus-wide) and
    # filters client-side, exactly as verified interactively, rather than
    # risking a per-building server-side filter silently no-op'ing back to
    # the unfiltered list (which would multiply facility calls per building
    # instead of scoping them).
    facility_rows = paged_fetch(client, CLASSROOMS_PATH, scope: "classrooms", array_path: [ "Classrooms", "Classroom" ])
    facility_ids_by_building = facility_rows.group_by { |row| row["BuildingID"] }
                                             .transform_values { |rows| rows.map { |row| row["FacilityID"] }.uniq }

    buildings_by_id.each_value do |building|
      facility_ids = facility_ids_by_building[building.bldrecnbr] || []
      facility_ids.each { |facility_id| apply_facility_characteristics(client, facility_id, rooms_by_rmrecnbr, stats) }
    end

    stats
  rescue => e
    # Never propagate: buildings/rooms/units are already committed row-by-row
    # above, so a hard failure here (exhausted rate-limit retries, an
    # unexpected response shape) should only truncate the characteristics
    # phase, not the whole task.
    warn "[um:import] characteristics phase failed after #{stats[:facility_calls]} facility call(s): #{e.class}: #{e.message}"
    stats
  end

  def apply_facility_characteristics(client, facility_id, rooms_by_rmrecnbr, stats)
    path = "#{CLASSROOMS_PATH}/#{URI.encode_www_form_component(facility_id)}/Characteristics"
    rows = client.rate_limiter.backoff_429 do
      body = client.get_json(path, scope: "classrooms")
      body.dig("Classrooms", "Classroom") || []
    end
    stats[:facility_calls] += 1

    rows.group_by { |row| row["RmRecNbr"] }.each do |rmrecnbr, char_rows|
      room = rooms_by_rmrecnbr[rmrecnbr]
      next unless room # facility covers a room outside this import's Classroom-typed set

      stats[:matched_rooms] += 1
      apply_room_characteristics(room, facility_id, char_rows, stats)
    end
  rescue UmApi::NotFound, UmApi::ServerError => e
    warn "[um:import]   facility #{facility_id} characteristics fetch failed (#{e.class}) — skipping"
  end

  def apply_room_characteristics(room, facility_id, char_rows, stats)
    room.update!(facility_code: facility_id) if room.facility_code != facility_id

    char_rows.each do |row|
      short_code = CodeNormalizer.normalize(row["ChrstcDescrShort"])
      next unless short_code

      room.room_characteristics.find_or_create_by!(code: row["Chrstc"]) do |rc|
        # Going through the `room.room_characteristics` association only
        # auto-fills room_id, not workspace_id (unlike the `for_current_workspace`
        # scope everything else here goes through) — mirrors
        # DevelopmentSampleData#seed_room_characteristics' explicit assignment.
        rc.workspace = room.workspace
        rc.short_code = short_code
        rc.description = row["ChrstcDescr"]
        rc.long_description = row["ChrstcDescr254"]
      end
      stats[:characteristic_rows] += 1
      stats[:display_rules_created] += 1 if ensure_display_rule!(short_code, row["ChrstcDescr"])
    end
  end

  # Reuses an existing display rule where short_code already matches (per
  # task brief: db/seeds/reference_data.yml already seeded a few of these,
  # some with invalid icon_keys — never touched here, only reused by
  # find_or_create_by's lookup half). Returns true only when a NEW row was
  # created, so the caller can count it.
  def ensure_display_rule!(short_code, description)
    created = false
    CharacteristicDisplayRule.for_current_workspace.find_or_create_by!(short_code: short_code) do |rule|
      rule.icon_key = icon_key_for(description)
      rule.filterable = true
      rule.team_learning = description.to_s.match?(/team/i)
      created = true
    end
    created
  end

  def icon_key_for(description)
    _pattern, icon = ICON_RULES.find { |pattern, _icon| description.to_s.match?(pattern) }
    icon = FALLBACK_ICON unless icon && IconRegistry.exists?(icon)
    icon
  end

  # === Summary ===

  def print_summary(workspace, client)
    puts "[um:import] done (#{client.call_count} gateway calls, #{client.rate_limiter.sleep_count} rate-limit sleeps). " \
         "#{workspace.slug} now has: " \
         "#{Building.where(workspace: workspace).count} buildings, " \
         "#{Floor.where(workspace: workspace).count} floors, " \
         "#{Room.where(workspace: workspace).count} rooms, " \
         "#{Room.for_current_workspace.classroom.listed.count} listed classrooms, " \
         "#{Unit.where(workspace: workspace).count} units, " \
         "#{Campus.where(workspace: workspace).count} campuses, " \
         "#{RoomCharacteristic.where(workspace: workspace).count} characteristics, " \
         "#{CharacteristicDisplayRule.where(workspace: workspace).count} display rules."
  end
end
