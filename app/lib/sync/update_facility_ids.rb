# Facility-ID sync — Task 10 of planning/plans/phase-2-ingestion.md (roadmap
# Lib section). Mirrors Sync::UpdateCampuses/UpdateBuildings/UpdateRooms's
# shape (real client, `Current.workspace` set by the caller, `changed_after_
# assign` for accurate counters, empty-feed guard on the stale sweep) but is
# the ONE deliberately adapted phase in the sync (spec D7;
# planning/specs/2026-07-07-mclassrooms-design.md).
#
# MATCH, NEVER CREATE: rooms already exist by the time this phase runs
# (Sync::UpdateRooms, Task 9, walks every building and ingests every room
# type — Brief §14.2). This phase only matches discovered rmrecnbrs to
# EXISTING rooms and writes `facility_code` and `campus` onto the match. A
# discovered rmrecnbr with no matching room is skipped and counted/warned —
# it is never used to build a new Room; that would duplicate
# Sync::UpdateRooms's job and could create a room with none of the
# building/floor/department context that phase assigns.
#
# THE CROSSWALK (sync-fix Task 4 — the structural rewrite of this phase):
# the real facility list (`GET /aa/ClassroomList/v2/Classrooms`, scope
# "classrooms") carries only `FacilityID`/`BuildingID`/`BldDescrShort`/
# `CampusCd`/`CampusDescr` — NO `RmRecNbr` and NO seat/Capacity field at
# all. The only place the FacilityID<->RmRecNbr crosswalk actually exists is
# each facility's own `/Characteristics` sub-resource (`GET
# /aa/ClassroomList/v2/Classrooms/{FacilityID}/Characteristics`, scope
# "classrooms"), whose rows carry `RmRecNbr`. So discovery is two steps,
# mirroring `UmImport.import_characteristics` (lib/tasks/um_import.rake) —
# the same live-validated recipe:
#   1. Fetch the full facility list ONCE (paged via `client.fetch_all`),
#      group client-side by `BuildingID` -> `{bldrecnbr => [facility_id, ...]}`.
#   2. For each in-scope building (`Building.for_current_workspace`, same
#      iteration Sync::UpdateRooms uses) and each of its facility IDs, fetch
#      that facility's `/Characteristics` to read the `RmRecNbr`(s) it
#      covers, and match/upsert `facility_code: facility_id` on the room by
#      rmrecnbr.
# A facility whose Characteristics response comes back empty is
# undiscoverable via this crosswalk — an accepted data gap in the proven
# recipe (see um-import-report.md: some real facilities never turn up any
# characteristics), not a bug to fix here; this phase warns on rooms it
# can't match rather than guessing (no prefix heuristics).
#
# Per-facility double-fetch (sync-fix-decisions.md Risk 2 — ACCEPTED, not
# resolved): Sync::UpdateCharacteristics independently re-fetches the SAME
# per-facility `/Characteristics` endpoint to store characteristic rows.
# This phase and that one deliberately stay architecturally independent for
# now (matches BasePhase's no-cross-phase-data-handoff design, keeps specs
# simple) — accept the ~2x per-facility call volume for now (nightly job,
# rate-limit-aware). FOLLOW-UP (explicitly out of scope for this fix): share
# one per-facility fetch across the two phases (merge the phases, or a
# RunPipeline per-run cache) to halve gateway volume.
#
# instructional_seat_count (sync-fix Task 4 — a real DESIGN CHANGE from the
# original best-effort guess): the real facility list has no seat/Capacity
# field at all, so this phase no longer touches instructional_seat_count at
# all — seats now come exclusively from Sync::UpdateRooms's own
# RoomInfo.RoomStationCount field, already populated by the time this phase
# runs (RunPipeline orders Sync::UpdateRooms before this phase). `campus`
# stays `room.building.campus` (matches UmImport exactly) — no change there.
#
# Per-facility backoff_429 (Brief §6.1 phase 4): unlike the old
# single-whole-walk retry, each per-facility Characteristics fetch is now
# its own network call, so it is individually wrapped in
# `client.rate_limiter.backoff_429` — the same per-item retry shape
# Sync::UpdateCharacteristics/UpdateContacts already use, not a whole-walk
# wrap. This also means the old "whole-walk retry restarts from page 1 and
# re-yields rows already counted" residual risk no longer applies: a 429 on
# one facility's fetch retries only THAT facility, never the facility list
# fetch or any other facility already processed this run. The facility
# LIST's own paged fetch (`client.fetch_all`) is still wrapped in ONE
# backoff_429 — it returns a plain Array rather than yielding incrementally,
# so a retry there just re-runs the whole paged fetch and reassigns the
# result, with no external state to reset (unlike the old each_page-based
# version, which needed a `seen.clear` workaround for exactly this reason).
#
# CLEAR-NOT-DEACTIVATE (the adaptation, unchanged by the Task 4 rewrite):
# the legacy app deactivated any room absent from the Classroom List feed —
# safe when the DB holds classrooms exclusively, which is no longer true
# now that Sync::UpdateRooms ingests every room type. Deactivating on
# classroom-list absence would wrongly retire every office and lab every
# night, since the classroom list never mentions them in the first place.
# Instead: a room that PREVIOUSLY had a facility_code but was not
# (re)discovered this run gets `facility_code: nil` (the phase-1
# `before_save` on Room recomputes `facility_code_normalized` to nil in the
# same write). That drops the room out of Find-a-Room via the D8 classroom
# scope (`Room.classroom` requires `facility_code` present) — the same
# user-visible effect as the old deactivation, but data-preserving and
# self-healing: if the room reappears in a later feed, its facility_code
# (and normalized twin) is simply restored on the next run. `in_feed` is
# NEVER touched here — it is owned solely by Sync::UpdateRooms. A room that
# never had a facility_code (a genuine non-classroom) is untouched by the
# sweep below, since it was never in the `where.not(facility_code: nil)`
# candidate set to begin with.
#
# Empty-feed guard (mirrors every other phase's stale-sweep — Task 7/8/9's
# exemplars): if discovery finds zero rmrecnbrs across every in-scope
# building's facilities, `seen` is empty and the clear-sweep is skipped
# with a warning rather than nil-ing every coded room's facility_code — a
# transient gateway glitch must never read as "every classroom was retired
# at once".
#
# Capacity bound recompute (D12): `Setting.recompute_capacity_filter_max!`
# runs at the very END of #perform, strictly after the upsert loop and the
# clear-sweep. RunPipeline runs Sync::UpdateRooms (seats' real source, per
# the Task 4 move above) BEFORE this phase, so seats are already populated
# when this recomputes the workspace-wide max. Placing the call last means
# it only ever executes once the rest of #perform has completed without
# raising: an earlier raise (e.g. a genuine DB error mid-upsert) propagates
# straight out of #perform to Sync::BasePhase's rescue, which fails the
# phase and never lets execution reach the recompute line — "after phase
# success" is enforced by ordinary control flow, not a special hook.
#
# preload_facility_ids_by_building(row) / fetch_facility_characteristics(row)
# isolation: per spec/support/um_api_stubs.rb's fixture-shape disclaimer,
# these are the ONLY two places that reach into a raw API response hash
# directly — FacilityID/BuildingID (facility list) and RmRecNbr
# (characteristics) are confirmed against live credentialed access
# (sync-fix Task 4; see the proven reference
# `lib/tasks/um_import.rake#import_characteristics`).
#
# Endpoint path ("/aa/ClassroomList/v2/Classrooms"): confirmed against live
# credentialed access (sync-fix Task 4) — replaces the earlier best-effort
# guess ("/bf/Buildings/v2/Classrooms").
module Sync
  class UpdateFacilityIds < BasePhase
    KEY = "facility_ids"

    FACILITY_LIST_PATH = "/aa/ClassroomList/v2/Classrooms"

    private

    def perform
      seen = []
      skipped_rmrecnbrs = Set.new
      facility_ids_by_building = preload_facility_ids_by_building

      Building.for_current_workspace.find_each do |building|
        (facility_ids_by_building[building.bldrecnbr] || []).each do |facility_id|
          apply_facility(facility_id, seen, skipped_rmrecnbrs)
        end
      end

      clear_stale_facility_codes(seen)
      Setting.recompute_capacity_filter_max!
    end

    # ONE paged fetch of the full facility list, grouped client-side by
    # BuildingID — see header comment (the same full-list-then-filter-
    # client-side caution UmImport.import_characteristics documents: the
    # gateway's own BuildingID query-param filtering on this endpoint is
    # unverified, so this fetches once and filters in Ruby rather than
    # risking a per-building server-side filter silently no-op'ing back to
    # the unfiltered list).
    def preload_facility_ids_by_building
      rows = client.rate_limiter.backoff_429 do
        client.fetch_all(FACILITY_LIST_PATH, array_path: %w[Classrooms Classroom], scope: "classrooms")
      end
      rows.group_by { |row| row["BuildingID"] }
          .transform_values { |group| group.map { |row| row["FacilityID"] }.uniq }
    end

    # Per-facility crosswalk discovery: reads the RmRecNbr(s) this facility
    # covers off its own Characteristics response (see header comment — the
    # facility list itself carries no RmRecNbr at all). A facility can cover
    # more than one room, so the response is grouped by RmRecNbr rather than
    # assumed 1:1.
    def apply_facility(facility_id, seen, skipped_rmrecnbrs)
      characteristic_rows = fetch_facility_characteristics(facility_id)

      characteristic_rows.group_by { |row| row["RmRecNbr"] }.each_key do |rmrecnbr|
        seen << rmrecnbr
        upsert_facility_id(rmrecnbr, facility_id, skipped_rmrecnbrs)
      end
    end

    # Wrapped individually in backoff_429 (a 429 here retries only THIS
    # facility, not the whole run — see header comment). A facility whose
    # fetch fails outright (NotFound/ServerError) is warned and skipped — an
    # accepted data gap (see header comment), not a phase failure.
    def fetch_facility_characteristics(facility_id)
      body = client.rate_limiter.backoff_429 do
        client.get_json("#{FACILITY_LIST_PATH}/#{ERB::Util.url_encode(facility_id)}/Characteristics", scope: "classrooms")
      end
      body.dig("Classrooms", "Classroom") || []
    rescue UmApi::NotFound, UmApi::ServerError => e
      add_warning("Facility #{facility_id} characteristics fetch failed (#{e.class}); crosswalk discovery skipped for this facility")
      []
    end

    # A discovered rmrecnbr with no matching room (Room.for_current_workspace
    # scoped, so a match never reaches into another tenant's data) is
    # skipped — see header comment: rooms come only from Sync::UpdateRooms,
    # never from this phase. `skipped_rmrecnbrs.add?` returns nil when the
    # rmrecnbr was already skipped this run (e.g. discovered under more than
    # one facility), so it is counted/warned at most once per run.
    def upsert_facility_id(rmrecnbr, facility_id, skipped_rmrecnbrs)
      room = Room.for_current_workspace.find_by(rmrecnbr: rmrecnbr)

      unless room
        if skipped_rmrecnbrs.add?(rmrecnbr)
          count(:skipped)
          add_warning("Classroom characteristics row #{rmrecnbr} (facility code #{facility_id}) has no matching room; skipped")
        end
        return
      end

      assignable = { facility_code: facility_id, campus: room.building.campus }

      count(:updated) if room.changed_after_assign(assignable)
      room.update!(assignable)
    end

    # See header comment: clear-not-deactivate (spec D7), empty-feed guard,
    # dry-run preview. Only rooms that currently HAVE a facility_code are
    # candidates at all — a non-classroom room (facility_code already nil)
    # never enters `stale` and is therefore never touched.
    def clear_stale_facility_codes(seen)
      if seen.empty?
        add_warning("Classroom facility crosswalk discovered zero rows this run; skipping facility_code clear sweep")
        return
      end

      stale = Room.for_current_workspace.where.not(facility_code: nil).where.not(rmrecnbr: seen)

      if dry_run?
        stale.find_each do |room|
          count(:cleared)
          add_warning("Room #{room.rmrecnbr} facility_code #{room.facility_code} would be cleared")
        end
        return
      end

      stale.find_each do |room|
        room.update!(facility_code: nil)
        count(:cleared)
      end
    end
  end
end
