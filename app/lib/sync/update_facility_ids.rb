# Facility-ID sync — Task 10 of planning/plans/phase-2-ingestion.md (roadmap
# Lib section). Mirrors Sync::UpdateCampuses/UpdateBuildings/UpdateRooms's
# shape (real client, `Current.workspace` set by the caller, `changed_after_
# assign` for accurate counters, empty-feed guard on the stale sweep) but is
# the ONE deliberately adapted phase in the sync (spec D7;
# planning/specs/2026-07-07-mclassrooms-design.md).
#
# MATCH, NEVER CREATE: rooms already exist by the time this phase runs
# (Sync::UpdateRooms, Task 9, walks every building and ingests every room
# type — Brief §14.2). This phase only matches Classroom List rows to
# EXISTING rooms by rmrecnbr and writes `facility_code`,
# `instructional_seat_count`, and `campus` onto the match. A row with no
# matching room is skipped and counted/warned — it is never used to build a
# new Room; that would duplicate Sync::UpdateRooms's job and could create a
# room with none of the building/floor/department context that phase
# assigns.
#
# CLEAR-NOT-DEACTIVATE (the adaptation): the legacy app deactivated any room
# absent from the Classroom List feed — safe when the DB holds classrooms
# exclusively, which is no longer true now that Sync::UpdateRooms ingests
# every room type. Deactivating on classroom-list absence would wrongly
# retire every office and lab every night, since the classroom list never
# mentions them in the first place. Instead: a room that PREVIOUSLY had a
# facility_code but has dropped out of the feed gets `facility_code: nil`
# (the phase-1 `before_save` on Room recomputes `facility_code_normalized`
# to nil in the same write). That drops the room out of Find-a-Room via the
# D8 classroom scope (`Room.classroom` requires `facility_code` present) —
# the same user-visible effect as the old deactivation, but data-preserving
# and self-healing: if the room reappears in a later feed, its facility_code
# (and normalized twin) is simply restored on the next run. `in_feed` is
# NEVER touched here — it is owned solely by Sync::UpdateRooms. A room that
# never had a facility_code (a genuine non-classroom) is untouched by the
# sweep below, since it was never in the `where.not(facility_code: nil)`
# candidate set to begin with.
#
# Empty-feed guard (mirrors every other phase's stale-sweep — Task 7/8/9's
# exemplars): if the classroom-list feed returns zero rows, `seen` is empty
# and the clear-sweep is skipped with a warning rather than nil-ing every
# coded room's facility_code — a transient gateway glitch must never read
# as "every classroom was retired at once".
#
# Per-item backoff_429 (Brief §6.1 phase 4): the classroom-list fetch is the
# only network call this phase makes (matching + clearing are pure Ruby/DB
# work against rooms already in this workspace), so the ENTIRE
# `client.each_page` walk is wrapped in `client.rate_limiter.backoff_429` —
# a transient 429 sleeps-and-retries the whole fetch instead of aborting the
# phase. `seen` is reset at the top of the wrapped block so a retry that
# fires after some rows were already yielded (a multi-page feed 429-ing on
# page 2, say) starts the seen-list clean rather than accumulating rmrecnbrs
# across attempts; re-running the upsert for an already-processed row is a
# harmless no-op (idempotent, same as every other phase's upsert).
#
# Capacity bound recompute (D12): `Setting.recompute_capacity_filter_max!`
# runs at the very END of #perform, strictly after the upsert loop and the
# clear-sweep — seat counts come from THIS feed, so the bound recomputes
# here rather than in Sync::UpdateRooms. Placing the call last means it only
# ever executes once the rest of #perform has completed without raising: an
# earlier raise (e.g. a genuine DB error mid-upsert) propagates straight out
# of #perform to Sync::BasePhase's rescue, which fails the phase and never
# lets execution reach the recompute line — "after phase success" is
# enforced by ordinary control flow, not a special hook.
#
# parse_classroom(row) isolation: per spec/support/um_api_stubs.rb's
# fixture-shape disclaimer, RmRecNbr/FacilityCd/Capacity match
# spec/fixtures/um_api/classroom_list.json exactly, NOT verified against
# credentialed access — if phase 8's cutover finds different field names,
# this is the only method that needs to change.
#
# Endpoint path ("/bf/Buildings/v2/Classrooms"): mirrors
# Sync::UpdateCampuses's own flat sub-resource off "/bf/Buildings/v2" — a
# best-effort guess pending phase 8's credentialed cutover, like every other
# phase's path constants.
module Sync
  class UpdateFacilityIds < BasePhase
    KEY = "facility_ids"

    CLASSROOM_LIST_PATH = "/bf/Buildings/v2/Classrooms"

    private

    def perform
      seen = []

      client.rate_limiter.backoff_429 do
        seen.clear
        client.each_page(CLASSROOM_LIST_PATH, scope: "classrooms") do |row|
          attrs = parse_classroom(row)
          seen << attrs[:rmrecnbr]
          upsert_facility_id(attrs)
        end
      end

      clear_stale_facility_codes(seen)
      Setting.recompute_capacity_filter_max!
    end

    # A classroom-list row with no matching room (Room.for_current_workspace
    # scoped, so a match never reaches into another tenant's data) is
    # skipped — see header comment: rooms come only from Sync::UpdateRooms,
    # never from this phase.
    def upsert_facility_id(attrs)
      room = Room.for_current_workspace.find_by(rmrecnbr: attrs[:rmrecnbr])

      unless room
        count(:skipped)
        add_warning("Classroom list row #{attrs[:rmrecnbr]} (facility code #{attrs[:facility_code]}) has no matching room; skipped")
        return
      end

      assignable = {
        facility_code: attrs[:facility_code],
        instructional_seat_count: attrs[:seat_count],
        campus: room.building.campus
      }

      count(:updated) if room.changed_after_assign(assignable)
      room.update!(assignable)
    end

    # See header comment: clear-not-deactivate (spec D7), empty-feed guard,
    # dry-run preview. Only rooms that currently HAVE a facility_code are
    # candidates at all — a non-classroom room (facility_code already nil)
    # never enters `stale` and is therefore never touched.
    def clear_stale_facility_codes(seen)
      if seen.empty?
        add_warning("Classroom list feed returned zero rows; skipping facility_code clear sweep")
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

    def parse_classroom(row)
      {
        rmrecnbr: row.fetch("RmRecNbr").to_s,
        facility_code: row["FacilityCd"],
        seat_count: row["Capacity"]
      }
    end
  end
end
