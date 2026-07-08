# Room sync — Task 9 of planning/plans/phase-2-ingestion.md (roadmap Lib
# section). The largest and most intricate of the six Sync::BasePhase
# subclasses: it walks a PER-BUILDING feed (not one flat endpoint like
# campuses/buildings), enriches every row from a second gateway resource
# (departments), and — unlike campuses (hard-delete, Task 7) or buildings
# (warn-only, Task 8) — DEACTIVATES rooms that drop out of the feed.
#
# ALL ROOM TYPES (Brief §14.2): every row returned per building is ingested —
# Classroom, Class Laboratory, Office, everything. There is deliberately NO
# `RoomType == "Classroom"` filter here, even though the legacy app applied
# one at ingestion time. `Room.classroom` (app/models/room.rb) is a DISPLAY
# scope for the Find-a-Room UI, not an ingestion rule — an Office row is a
# real room this app needs to know about (for department/unit assignment,
# characteristics, contacts in later phases), it just never shows up in the
# classroom-only listing.
#
# Per-building walk: rooms have no flat listing endpoint of their own in this
# gateway's shape (unlike Campuses, a flat sub-resource of Buildings) — the
# feed is inherently per-building, so #perform iterates
# `Building.for_current_workspace` (already scope-filtered by
# Sync::UpdateBuildings, Task 8 — this phase does no scope filtering of its
# own) and calls `#each_page` once per building. `rooms_path` mirrors
# UpdateBuildings's own "/bf/Buildings/v2" prefix for internal consistency;
# like FISCAL_YEAR_PARAM there, this is a best-effort guess pending phase 8's
# credentialed cutover (see spec/support/um_api_stubs.rb's fixture-shape
# disclaimer) — only this method needs to change if the real path differs.
#
# floor_id / unit_id (D10 / Brief §14.1): `Floor.find_or_create_by!(building:,
# label:)` creates the floor once per (building, label) — the DB's own
# `[building_id, label]` unique index (db/schema.rb) makes this safe to call
# on every room on that floor, every run. `Unit.find_or_create_by!
# (department_group: group_description)` — note the department GROUP
# DESCRIPTION (the long readable text, e.g. "College of Literature, Science &
# the Arts"), not the short group code — is skipped entirely (unit_id: nil)
# when that description is blank, which is exactly the admin-only-room case
# (Brief §14.1): a room with no department group has no unit to assign.
# Both lookups are scoped `.for_current_workspace` (matching Sync::
# UpdateCampuses's `find_or_initialize_by` precedent) so a brand-new Floor or
# Unit is stamped with this run's workspace via `scope_for_create`, and two
# workspaces never collide on the same (building, label) or department_group.
#
# Department enrichment (performance — Task 8's review flagged per-row Campus
# lookups in UpdateBuildings; this phase has far higher row volume, so it
# matters more here): `#preload_departments` makes ONE paged fetch before any
# building is walked, building a `{dept_id => {description:, group:,
# group_description:}}` hash. Every room's lookup after that is an O(1) hash
# read — NOT a per-row gateway call. Only when a room's department id is
# missing from that hash does `#fetch_department_fallback` make an
# individual `get_json` call, and even that is wrapped in
# `client.rate_limiter.backoff_429` so a transient 429 during the fallback
# sleeps-and-retries instead of aborting the whole phase (same tool
# UmApi::RateLimiter already gives every phase, roadmap Task 4). A room
# whose department id is blank (the common admin-room case) never triggers
# either path — there is nothing to look up.
#
# Deactivation sweep (Brief §6.1 phase 3 / §8.4: deactivate, never delete):
# after every building has been walked, `#deactivate_stale_rooms` flips
# `in_feed: false` on every workspace room whose rmrecnbr was NOT seen this
# run. Two guards, both mirroring Sync::UpdateCampuses's resilience pattern
# (Task 7 — the exemplar Task 8's review generalized into "every stale-sweep
# must guard empty feed"):
#
# 1. Empty-feed guard: if `seen` is empty (every building's feed returned
#    zero rows, or there were no buildings to walk at all), skip the sweep
#    and warn — a transient gateway glitch must never read as "every room at
#    every building was retired at once".
# 2. Single transaction, all-or-nothing (Brief §6.1: "all-or-nothing per run
#    via a transaction") — deliberately NOT per-record-rescued like
#    UpdateCampuses's FK-safe delete. A room deactivation has no FK
#    dependents to worry about, so there is no legitimate per-record failure
#    to tolerate; if ANY deactivation in the batch raises, the whole
#    transaction rolls back rather than leaving the room table in a
#    half-deactivated state. That raise then propagates out of #perform,
#    which Sync::BasePhase's `.call` rescue turns into a failed phase and a
#    Result.failure — by design (see BasePhase's own header comment: "fail
#    this phase, keep whatever it counted so far, never propagate"), so the
#    in-memory `counters[:deactivated]` may reflect more than actually
#    persisted after a rollback. That is intentional and harmless: it is a
#    Ruby-side counter, not a second source of truth, and the phase's FAILED
#    status is what actually surfaces the problem to Task 12's pipeline.
#
# hidden_at / hidden_by_id (D6, curation-owned) never appear in `room_attrs`
# below, so `update!` never touches them — deactivating (or reactivating) a
# room leaves its hidden state exactly as curation left it, in both
# directions.
#
# Dry-run (Brief §6.1 API_UPDATE_DELETE_DRY_RUN): mirrors UpdateCampuses's
# explicit dry-run branch in `delete_stale_campuses` rather than
# `guarded_write` — the phase needs to keep counting AND warn-with-rmrecnbr
# for every "would deactivate" room even though nothing is written, which
# `guarded_write`'s single yield/skip can't cleanly express (see that
# exemplar's own header comment for the identical reasoning). The
# create/update upsert itself is never guarded: it is the routine, idempotent
# half of this phase, only the deactivation is the destructive write dry-run
# exists to preview.
#
# parse_room(row) / parse_department(row) isolation: per spec/support/
# um_api_stubs.rb's fixture-shape disclaimer, these are the ONLY two places
# that reach into a raw API response hash directly. RmRecNbr/BldRecNbr/
# RoomNbr/RoomType/DeptID/SqFt/Floor (rooms) and DeptID/DeptDescr/DeptGrp/
# DeptGrpDescr (departments) match spec/fixtures/um_api/rooms_*.json and
# departments.json exactly, NOT verified against credentialed access — if
# phase 8's cutover finds different field names or endpoint paths, only
# these two methods and the two path constants below need to change.
module Sync
  class UpdateRooms < BasePhase
    KEY = "rooms"

    BUILDINGS_PATH = "/bf/Buildings/v2"
    DEPARTMENTS_PATH = "/bf/Buildings/v2/Departments"

    private

    def perform
      department_lookup = preload_departments
      seen = []

      Building.for_current_workspace.find_each do |building|
        client.each_page(rooms_path(building), scope: "buildings") do |row|
          attrs = parse_room(row)
          seen << attrs[:rmrecnbr]
          upsert_room(attrs, building, department_lookup)
        end
      end

      deactivate_stale_rooms(seen)
    end

    def rooms_path(building) = "#{BUILDINGS_PATH}/#{building.bldrecnbr}/Rooms"

    # ONE paged fetch, built before any building is walked — see header
    # comment. Keyed by department id (string) so per-room lookups below are
    # a plain hash read.
    def preload_departments
      lookup = {}
      client.each_page(DEPARTMENTS_PATH, scope: "department") do |row|
        lookup[row.fetch("DeptID").to_s] = parse_department(row)
      end
      lookup
    end

    # Individual per-department fallback for a room whose department id
    # wasn't in the bulk preload. `backoff_429` (UmApi::RateLimiter, Task 4)
    # sleeps-and-retries on a transient 429 instead of aborting the phase;
    # `client.rate_limiter` is the same reader Sync::BasePhase itself uses to
    # compute `rate_limit_sleeps` (see that class's header comment), so a
    # sleep triggered here is counted the same way.
    def fetch_department_fallback(department_id)
      row = client.rate_limiter.backoff_429 do
        client.get_json("#{DEPARTMENTS_PATH}/#{department_id}", scope: "department")
      end
      parse_department(row)
    end

    def upsert_room(attrs, building, department_lookup)
      dept_attrs = department_attrs(attrs[:department_id], department_lookup)
      floor = Floor.for_current_workspace.find_or_create_by!(building: building, label: attrs[:floor_label])

      assignable = {
        building: building,
        building_name: building.name,
        floor: floor,
        unit_id: resolve_unit_id(dept_attrs[:department_group_description]),
        department_id: attrs[:department_id],
        room_number: attrs[:room_number],
        room_type: attrs[:room_type],
        square_feet: attrs[:square_feet],
        in_feed: true
      }.merge(dept_attrs)

      room = Room.for_current_workspace.find_or_initialize_by(rmrecnbr: attrs[:rmrecnbr])
      is_new = room.new_record?
      is_new ? count(:created) : (count(:updated) if room.changed_after_assign(assignable))
      room.update!(assignable)
    end

    # Blank department id (the admin-room case, Brief §14.1) skips
    # enrichment entirely — nothing to look up, nothing to assign.
    def department_attrs(department_id, department_lookup)
      return { department_description: nil, department_group: nil, department_group_description: nil } if department_id.blank?

      enrichment = department_lookup[department_id] || fetch_department_fallback(department_id)
      {
        department_description: enrichment[:description],
        department_group: enrichment[:group],
        department_group_description: enrichment[:group_description]
      }
    end

    # nil when the department GROUP DESCRIPTION is blank (Brief §14.1) — a
    # room with no department group is admin-only and gets no unit.
    def resolve_unit_id(group_description)
      return nil if group_description.blank?

      Unit.for_current_workspace.find_or_create_by!(department_group: group_description).id
    end

    # See header comment: empty-feed guard, then a single all-or-nothing
    # transaction (real runs) or a pure count+warn preview (dry run).
    def deactivate_stale_rooms(seen)
      if seen.empty?
        add_warning("Rooms feed returned zero rows across all buildings; skipping deactivation")
        return
      end

      stale = Room.for_current_workspace.where.not(rmrecnbr: seen)

      if dry_run?
        stale.find_each do |room|
          count(:deactivated)
          add_warning("Room #{room.rmrecnbr} would be deactivated")
        end
        return
      end

      ActiveRecord::Base.transaction do
        stale.find_each do |room|
          room.update!(in_feed: false)
          count(:deactivated)
        end
      end
    end

    def parse_room(row)
      {
        rmrecnbr: row.fetch("RmRecNbr").to_s,
        room_number: row["RoomNbr"],
        room_type: row["RoomType"],
        department_id: row["DeptID"].to_s.presence,
        square_feet: row["SqFt"],
        floor_label: row.fetch("Floor").to_s
      }
    end

    def parse_department(row)
      {
        description: row["DeptDescr"],
        group: row["DeptGrp"],
        group_description: row["DeptGrpDescr"]
      }
    end
  end
end
