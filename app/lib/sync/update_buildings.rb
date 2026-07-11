# Building sync — Task 8 of planning/plans/phase-2-ingestion.md (roadmap Lib
# section). Mirrors Sync::UpdateCampuses's shape (Task 7: real client,
# `.for_current_workspace` scoping via Current.workspace set by the caller,
# `changed_after_assign` for accurate created/updated counters) with two
# structural differences the brief calls out:
#
# 1. Scope filtering (Brief §6.1/§8.2). The feed returns every building
#    U-M-wide; SyncScopeRule (phase 1) narrows that to what this workspace
#    actually tracks. A row is in scope when
#    (its campus code is campus_allow-listed OR its own bldrecnbr is
#    building_allow-listed) AND its bldrecnbr is NOT building_exclude-listed
#    — exclude wins even over an explicit building_allow entry for the same
#    bldrecnbr, since it's checked first and short-circuits. Rules are
#    loaded ONCE per run (three `.pluck(:value)` calls), not re-queried
#    per-row.
#
# 2. Warn-only absence (Brief §8.4) — the one place buildings genuinely
#    differ from campuses (hard-delete, Task 7) and rooms (deactivate,
#    Task 10): a building absent from the feed is neither destroyed nor
#    flagged `in_feed: false`. It is left exactly as-is, plus one warning
#    naming its bldrecnbr. `feed_bldrecnbrs` below collects every row the
#    API actually returned BEFORE scope filtering is applied, specifically
#    so that a building this workspace chooses to exclude via
#    SyncScopeRule — genuinely present upstream, just not ingested here —
#    is never mistaken for "absent from the feed" and warned about.
#
# hidden_at / hidden_by_id (D6, curation-owned) are deliberately absent
# from `building_attrs` below, so `update!` never touches them — a hidden
# building stays hidden across any number of sync runs; no special-case
# code needed, just omission.
#
# Dry-run: per BasePhase's contract, `guarded_write` wraps only a phase's
# destructive write; the create/update upsert always runs (see
# Sync::UpdateCampuses's own header comment for the same rule). Buildings
# have no destructive write at all — add_warning is not a mutation — so
# there is nothing here to guard.
#
# parse_building(row) isolation: BuildingRecordNumber/BuildingLongDescription/
# BuildingShortDescription/BuildingCampusCode/BuildingStreetNumber/
# BuildingStreetDirection/BuildingStreetName/BuildingCity/BuildingState/
# BuildingPostal are confirmed against live credentialed access (sync-fix
# Task 2; see the proven reference
# `lib/tasks/um_import.rake#upsert_building`/`#building_address`) — no other
# code reaches into a raw API response hash directly, so a future field-name
# change (unlikely; this endpoint is already verified) would still only
# touch this one method. `Country` is NOT in the feed at all — hardcoded to
# "USA" here, matching `UmImport.upsert_building`.
#
# BuildingCampusDescription IS present per-row on BuildingInfo, but
# `buildings.campus_description` isn't a real column (only `Campus#description`
# is) — so it's deliberately left out of parse_building's return value rather
# than parsed-and-discarded. Collapsing Sync::UpdateCampuses into this phase
# (deriving Campus rows straight from Buildings rows, the way
# `UmImport.import_campuses` does) is a live option given that overlap, but
# is an optional redesign, not required by this fix (Sync::UpdateCampuses's
# own dedicated endpoint already works) — out of scope here.
#
# Endpoint: `GET /bf/Buildings/v2/BuildingInfo` (BUILDING_INFO_PATH), scope
# "buildings", paged via `client.fetch_all` (UmApi::Client, sync-fix Task 1)
# digging the real two-level envelope (`resp["ListOfBldgs"]["Buildings"]`).
# No fiscal-year param: BuildingInfo doesn't scope by fiscal year at all —
# the old `FISCAL_YEAR_PARAM`/`UmApi.fiscal_year(Date.current)` pairing was a
# guess against the wrong endpoint and is dropped outright (UmApi.fiscal_year
# itself stays defined; other still-unmigrated phases/comments may reference
# it).
module Sync
  class UpdateBuildings < BasePhase
    KEY = "buildings"

    BUILDING_INFO_PATH = "/bf/Buildings/v2/BuildingInfo"

    private

    def perform
      allowed_campuses = SyncScopeRule.for_current_workspace.campus_allow.pluck(:value)
      allowed_buildings = SyncScopeRule.for_current_workspace.building_allow.pluck(:value)
      excluded_buildings = SyncScopeRule.for_current_workspace.building_exclude.pluck(:value)

      feed_bldrecnbrs = []

      rows = client.fetch_all(BUILDING_INFO_PATH, array_path: %w[ListOfBldgs Buildings], scope: "buildings")

      rows.each do |row|
        attrs = parse_building(row)
        feed_bldrecnbrs << attrs[:bldrecnbr]

        next unless in_scope?(attrs, allowed_campuses, allowed_buildings, excluded_buildings)

        upsert_building(attrs)
      end

      warn_absent_buildings(feed_bldrecnbrs)
    end

    def in_scope?(attrs, allowed_campuses, allowed_buildings, excluded_buildings)
      return false if excluded_buildings.include?(attrs[:bldrecnbr])

      allowed_campuses.include?(attrs[:campus_code]) || allowed_buildings.include?(attrs[:bldrecnbr])
    end

    def upsert_building(attrs)
      building = Building.for_current_workspace.find_or_initialize_by(bldrecnbr: attrs[:bldrecnbr])
      is_new = building.new_record?
      assignable = building_attrs(attrs)

      is_new ? count(:created) : (count(:updated) if building.changed_after_assign(assignable))
      building.update!(assignable)

      GeocodeBuildingJob.perform_later(building.id) if is_new
    end

    # Sync-owned columns only (Brief §6.1: create/update sets `in_feed:
    # true`) — hidden_at/hidden_by_id are curation-owned (D6) and
    # deliberately absent so update! never touches them.
    def building_attrs(attrs)
      {
        name: attrs[:name],
        abbreviation: attrs[:abbreviation],
        address: attrs[:address],
        city: attrs[:city],
        state: attrs[:state],
        zip: attrs[:zip],
        country: attrs[:country],
        campus: Campus.for_current_workspace.find_by(code: attrs[:campus_code]),
        in_feed: true
      }
    end

    # Warn-only absence sweep (Brief §8.4) — the buildings analog of
    # Sync::UpdateCampuses#delete_stale_campuses, but it never mutates a
    # row. Empty-feed guard mirrors that exemplar's rationale (a zero-row
    # response reads as a transient gateway glitch, not "every building was
    # retired"), collapsed to ONE summary warning instead of one per
    # pre-existing building so a genuine outage doesn't flood the run
    # report with a warning per row in the whole table.
    def warn_absent_buildings(feed_bldrecnbrs)
      if feed_bldrecnbrs.empty?
        add_warning("Buildings feed returned zero rows; skipping absence check")
        return
      end

      Building.for_current_workspace.where.not(bldrecnbr: feed_bldrecnbrs).find_each do |building|
        add_warning("Building #{building.bldrecnbr} is absent from the feed")
      end
    end

    def parse_building(row)
      {
        bldrecnbr: row.fetch("BuildingRecordNumber").to_s,
        campus_code: row.fetch("BuildingCampusCode").to_s,
        name: row.fetch("BuildingLongDescription"),
        abbreviation: row["BuildingShortDescription"],
        address: [ row["BuildingStreetNumber"], row["BuildingStreetDirection"], row["BuildingStreetName"] ].compact_blank.join(" "),
        city: row["BuildingCity"],
        state: row["BuildingState"],
        zip: row["BuildingPostal"],
        country: "USA"
      }
    end
  end
end
