# Characteristics sync — Task 11 (phase A) of planning/plans/phase-2-ingestion.md
# (roadmap Lib section; Brief §6.1 phase 5). The first of the two lightweight
# PER-CLASSROOM phases: unlike Sync::UpdateRooms/UpdateFacilityIds (one feed
# walked once, or once per building), there is no bulk characteristics
# listing endpoint — the gateway exposes characteristics one FACILITY at a
# time, keyed by facility_code. #perform iterates every facility-coded room
# (Room.for_current_workspace.where.not(facility_code: nil) — only
# classrooms carry a facility_code, D8) and makes ONE API call per room,
# mirroring Sync::UpdateRooms's #fetch_department_fallback shape: each
# per-room fetch is individually wrapped in client.rate_limiter.backoff_429
# (NOT one backoff wrapping a whole feed walk, the way UpdateFacilityIds's
# facility-list fetch is wrapped — there is no single feed here to wrap; a
# 429 on one room's fetch must not force a retry of every other room already
# processed this run).
#
# A facility can cover MORE THAN ONE ROOM (sync-fix Task 4 — the structural
# change of this rewrite): the real endpoint
# (`GET /aa/ClassroomList/v2/Classrooms/{FacilityID}/Characteristics`, scope
# "classrooms") is keyed by facility_code, not by room, and its response
# rows carry their own `RmRecNbr` — the SAME crosswalk field
# Sync::UpdateFacilityIds reads off this identical endpoint (accepted
# per-facility double-fetch, sync-fix-decisions.md Risk 2 — see that
# phase's header comment). Two rooms can legitimately share one
# facility_code, so #characteristics_for groups the response by RmRecNbr
# and applies only the group matching THIS room's rmrecnbr — a room whose
# own rmrecnbr has no group in the response is treated exactly like an
# empty response for that room (see below).
#
# PER-ROOM diff, not a whole-table sweep (this is the crux of the phase): for
# each room, the (RmRecNbr-filtered) response is the complete, authoritative
# set of characteristics for THAT room only. #sync_characteristics diffs it
# against room.room_characteristics, keyed on the natural key `code`
# (RoomCharacteristic's own uniqueness scope, db/schema.rb) — CREATE any code
# present in the response but missing from the DB, DELETE any code present in
# the DB but missing from the response. An empty response for one room is not
# a signal to skip that room's sweep (the empty-feed guard every other
# phase's WHOLE-TABLE stale-sweep needs, Task 7's resilience pattern) — it
# means exactly what it says: this room legitimately has zero characteristics
# right now, so every existing row for it is removed. There is no cross-room
# delete-all failure mode here the way a single blank feed would wrongly
# deactivate every room in Sync::UpdateRooms: this loop never touches any
# room but the one whose (filtered) response it just received.
#
# No "updated" counter / no in-place attribute refresh (the counters this
# phase reports are added/removed/api_calls/rate_limit_sleeps only): a code
# present in both the response and the DB is left completely alone — matched
# characteristics are neither re-saved nor compared field-by-field. This
# keeps every write this phase performs a plain create or a plain destroy, so
# D14's "ensure characteristic writes touch updated_at" is satisfied by
# ordinary ActiveRecord timestamp behavior with no extra bookkeeping — no
# Setting stamp is written here; phase 3's CharacteristicFilterGroups.data_
# version derives its cache key from RoomCharacteristic's own row count and
# max(updated_at) directly.
#
# Dry-run: matches Sync::UpdateFacilityIds's explicit-branch style (count +
# warn, no write) rather than guarded_write, since a departed characteristic
# needs to be both counted and named under dry-run — create is never
# guarded (routine, idempotent, per BasePhase's own guarded_write doc
# comment), only the destroy path is.
#
# Short-code normalization (Brief §6.1 phase 5): #normalize_short_code reuses
# the exact transform Room.normalize_facility_code already established in
# phase 1 (downcase, strip everything but [a-z0-9]) — the roadmap explicitly
# calls this "phase-1 rule", so short_code storage follows the one
# normalization convention this codebase already has rather than inventing a
# second one. "Whtbrd>25" (characteristics_MLB1200.json) becomes "whtbrd25".
#
# parse_characteristic(row) / characteristics_from(body) isolation: per
# spec/support/um_api_stubs.rb's fixture-shape disclaimer, these are the ONLY
# two places that reach into a raw API response hash directly. `Chrstc`
# (int, per ground truth — coerced `.to_s` at the parse boundary since
# RoomCharacteristic.code is a string column), `ChrstcDescrShort`,
# `ChrstcDescr`, `ChrstcDescr254`, and `RmRecNbr` (parse_characteristic /
# the RmRecNbr grouping above) are confirmed against live credentialed
# access (sync-fix Task 4). There is no `Status` field in the real shape at
# all — `status` is written as `nil` (RoomCharacteristic.status has no NOT
# NULL constraint, `t.string "status"`, so nil is safe); if this is ever
# promoted to a real column write, only this method needs to change.
#
# Endpoint path ("/aa/ClassroomList/v2/Classrooms"): confirmed against live
# credentialed access (sync-fix Task 4) — replaces the earlier best-effort
# guess ("/bf/Buildings/v2/Classrooms"); the "Characteristics" sub-resource
# segment is unchanged.
module Sync
  class UpdateCharacteristics < BasePhase
    KEY = "characteristics"

    CLASSROOMS_PATH = "/aa/ClassroomList/v2/Classrooms"

    private

    def perform
      Room.for_current_workspace.where.not(facility_code: nil).find_each do |room|
        sync_characteristics(room)
      end
    end

    def characteristics_path(facility_code) = "#{CLASSROOMS_PATH}/#{ERB::Util.url_encode(facility_code)}/Characteristics"

    def sync_characteristics(room)
      existing = room.room_characteristics.index_by(&:code)
      seen = Set.new

      characteristics_for(room).each do |row|
        attrs = parse_characteristic(row)
        next if skip_blank_short_code?(room, attrs)

        seen << attrs[:code]
        create_missing_characteristic(room, existing, attrs)
      end

      remove_departed_characteristics(room, existing, seen)
    end

    # CodeNormalizer.normalize returns nil for a short code that is blank or
    # all-punctuation. RoomCharacteristic validates short_code presence, so
    # attempting to create such a row raises RecordInvalid — which, unrescued
    # inside #perform's find_each, would abort characteristic sync for every
    # LATER room this run. Skip the unstorable row instead: don't add it to
    # `seen` (nothing to keep) and don't try to create it, counting/warning
    # once so the run report still surfaces the malformed feed row.
    def skip_blank_short_code?(room, attrs)
      return false if attrs[:short_code].present?

      count(:skipped)
      add_warning("Room #{room.rmrecnbr} characteristic #{attrs[:code]} has a blank short code after normalization; skipped")
      true
    end

    # Facility-keyed fetch, room-filtered result — see header comment: a
    # facility can cover more than one room, so the response is grouped by
    # RmRecNbr and only the group matching THIS room's rmrecnbr is returned.
    # A room whose rmrecnbr has no group in the response (including a wholly
    # empty response) gets an empty Array, which #sync_characteristics
    # treats as "this room legitimately has zero characteristics right now".
    def characteristics_for(room)
      body = client.rate_limiter.backoff_429 do
        client.get_json(characteristics_path(room.facility_code), scope: "classrooms")
      end
      characteristics_from(body).group_by { |row| row["RmRecNbr"].to_s }[room.rmrecnbr.to_s] || []
    end

    # Single documented raw-access point for the response envelope's shape —
    # see header comment. If a future cutover finds the envelope shaped
    # differently, only this method needs to change.
    def characteristics_from(body) = body.dig("Classrooms", "Classroom") || []

    # Routine, idempotent create — never dry-run guarded (see header
    # comment). A code already present in `existing` is left completely
    # alone: no update, no re-save.
    def create_missing_characteristic(room, existing, attrs)
      return if existing.key?(attrs[:code])

      room.room_characteristics.create!(
        workspace: room.workspace,
        code: attrs[:code],
        short_code: attrs[:short_code],
        description: attrs[:description],
        long_description: attrs[:long_description],
        status: attrs[:status]
      )
      count(:added)
    end

    # See header comment: per-room diff, dry-run counts+warns without
    # writing (mirrors Sync::UpdateFacilityIds's clear_stale_facility_codes
    # branch style), a real run destroys. No transaction wraps this loop —
    # unlike Sync::UpdateRooms's whole-table deactivation sweep, a partial
    # failure here leaves at most a few stale rows for THIS room, which the
    # next run's per-room diff cleans up on its own; RoomCharacteristic has
    # no FK dependents to protect.
    def remove_departed_characteristics(room, existing, seen)
      existing.each do |code, characteristic|
        next if seen.include?(code)

        if dry_run?
          count(:removed)
          add_warning("Room #{room.rmrecnbr} characteristic #{code} would be removed")
        else
          characteristic.destroy!
          count(:removed)
        end
      end
    end

    # short_code runs through the shared CodeNormalizer (app/lib) — the SAME
    # transform CharacteristicDisplayRule#normalize_short_code uses — so
    # phase 3's join across the two tables matches. It returns nil for a
    # blank/all-punctuation code, which #skip_blank_short_code? then filters
    # out. "Whtbrd>25" -> "whtbrd25". `Chrstc` is an int per ground truth
    # (RoomCharacteristic.code is a string column, hence `.to_s`); there is
    # no real `Status` source, so `status` is always nil (see header
    # comment).
    def parse_characteristic(row)
      {
        code: row.fetch("Chrstc").to_s,
        short_code: CodeNormalizer.normalize(row["ChrstcDescrShort"]),
        description: row["ChrstcDescr"],
        long_description: row["ChrstcDescr254"],
        status: nil
      }
    end
  end
end
