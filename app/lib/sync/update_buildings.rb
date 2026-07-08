# Building sync — Task 8 of planning/plans/phase-2-ingestion.md (roadmap Lib
# section). Mirrors Sync::UpdateCampuses's shape (Task 7: real client,
# `.for_current_workspace` scoping via Current.workspace set by the caller,
# `changed_after_assign` for accurate created/updated counters) with two
# structural differences the brief calls out:
#
# 1. Scope filtering (Brief §6.1/§8.2). The feed returns every building
#    U-M-wide for the current fiscal year; SyncScopeRule (phase 1) narrows
#    that to what this workspace actually tracks. A row is in scope when
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
# parse_building(row) isolation: per spec/support/um_api_stubs.rb's
# fixture-shape disclaimer, BldRecNbr/BldName/BldNameShort/CampusCd/
# Address/City/State/Zip/Country match spec/fixtures/um_api/
# buildings_page*.json exactly, NOT verified against credentialed access.
# If phase 8's live cutover finds different field names, this is the only
# method that needs to change.
#
# Endpoint path: "/bf/Buildings/v2" mirrors spec/lib/um_api/client_spec.rb's
# #each_page examples, which already exercise real pagination against this
# exact path with these exact fixtures — the strongest available signal for
# the real listing endpoint (Campuses hangs off it as a sub-resource,
# "/bf/Buildings/v2/Campuses"). The fiscal-year query param name
# ("fiscalYear") is this phase's best-effort guess, like PAGE_SIZE_PARAM in
# UmApi::Client — only this constant needs to change if phase 8 finds a
# different name.
module Sync
  class UpdateBuildings < BasePhase
    KEY = "buildings"

    FISCAL_YEAR_PARAM = "fiscalYear"

    private

    def perform
      allowed_campuses = SyncScopeRule.for_current_workspace.campus_allow.pluck(:value)
      allowed_buildings = SyncScopeRule.for_current_workspace.building_allow.pluck(:value)
      excluded_buildings = SyncScopeRule.for_current_workspace.building_exclude.pluck(:value)

      feed_bldrecnbrs = []

      client.each_page(
        "/bf/Buildings/v2",
        params: { FISCAL_YEAR_PARAM => UmApi.fiscal_year(Date.current) },
        scope: "buildings"
      ) do |row|
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
        bldrecnbr: row.fetch("BldRecNbr").to_s,
        campus_code: row.fetch("CampusCd").to_s,
        name: row.fetch("BldName"),
        abbreviation: row["BldNameShort"],
        address: row["Address"],
        city: row["City"],
        state: row["State"],
        zip: row["Zip"],
        country: row["Country"]
      }
    end
  end
end
