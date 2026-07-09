# Characteristics sync — Task 11 (phase A) of planning/plans/phase-2-ingestion.md
# (roadmap Lib section; Brief §6.1 phase 5). The first of the two lightweight
# PER-CLASSROOM phases: unlike Sync::UpdateRooms/UpdateFacilityIds (one feed
# walked once, or once per building), there is no bulk characteristics
# listing endpoint — the gateway exposes characteristics one classroom at a
# time, keyed by facility_code. #perform iterates every facility-coded room
# (Room.for_current_workspace.where.not(facility_code: nil) — only
# classrooms carry a facility_code, D8) and makes ONE API call per room,
# mirroring Sync::UpdateRooms's #fetch_department_fallback shape: each
# per-room fetch is individually wrapped in client.rate_limiter.backoff_429
# (NOT one backoff wrapping the whole loop, the way UpdateFacilityIds wraps
# its single whole-feed walk — there is no single feed here to wrap; a 429
# on one room's fetch must not force a retry of every other room already
# processed this run).
#
# PER-ROOM diff, not a whole-table sweep (this is the crux of the phase): for
# each room, the API response for THAT classroom is the complete,
# authoritative set of characteristics for THAT room only. #sync_characteristics
# diffs it against room.room_characteristics, keyed on the natural key `code`
# (RoomCharacteristic's own uniqueness scope, db/schema.rb) — CREATE any code
# present in the response but missing from the DB, DELETE any code present in
# the DB but missing from the response. An empty response for one room is not
# a signal to skip that room's sweep (the empty-feed guard every other
# phase's WHOLE-TABLE stale-sweep needs, Task 7's resilience pattern) — it
# means exactly what it says: this room legitimately has zero characteristics
# right now, so every existing row for it is removed. There is no cross-room
# delete-all failure mode here the way a single blank feed would wrongly
# deactivate every room in Sync::UpdateRooms: this loop never touches any
# room but the one whose response it just received.
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
# parse_characteristic(row) isolation: per spec/support/um_api_stubs.rb's
# fixture-shape disclaimer, Code/ShortCode/Description/LongDescription/Status
# match spec/fixtures/um_api/characteristics_MLB1200.json exactly, NOT
# verified against credentialed access — if phase 8's cutover finds different
# field names, only this method (and the normalization rule, if the real
# gateway turns out to pre-normalize) needs to change.
#
# Endpoint path ("/bf/Buildings/v2/Classrooms/{facility_code}/Characteristics"):
# mirrors Sync::UpdateFacilityIds's own "/bf/Buildings/v2/Classrooms" flat
# listing endpoint as its parent, nested per-classroom the way
# Sync::UpdateRooms nests its per-building Rooms endpoint off Buildings — a
# best-effort guess pending phase 8's credentialed cutover, like every other
# phase's path constants.
module Sync
  class UpdateCharacteristics < BasePhase
    KEY = "characteristics"

    CLASSROOMS_PATH = "/bf/Buildings/v2/Classrooms"

    private

    def perform
      Room.for_current_workspace.where.not(facility_code: nil).find_each do |room|
        sync_characteristics(room)
      end
    end

    def characteristics_path(facility_code) = "#{CLASSROOMS_PATH}/#{facility_code}/Characteristics"

    def sync_characteristics(room)
      existing = room.room_characteristics.index_by(&:code)
      seen = Set.new

      fetch_characteristics(room).each do |row|
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

    def fetch_characteristics(room)
      body = client.rate_limiter.backoff_429 do
        client.get_json(characteristics_path(room.facility_code), scope: "classrooms")
      end
      body.fetch("Characteristics", [])
    end

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
    # out. "Whtbrd>25" -> "whtbrd25".
    def parse_characteristic(row)
      {
        code: row.fetch("Code"),
        short_code: CodeNormalizer.normalize(row["ShortCode"]),
        description: row["Description"],
        long_description: row["LongDescription"],
        status: row["Status"]
      }
    end
  end
end
