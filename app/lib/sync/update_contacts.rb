# Contacts sync — Task 11 (phase B) of planning/plans/phase-2-ingestion.md
# (roadmap Lib section; Brief §6.1 phase 6). The second of the two
# lightweight per-classroom phases (see Sync::UpdateCharacteristics's header
# comment for the shared shape: no bulk listing endpoint, one API call per
# facility-coded room, each wrapped individually in
# client.rate_limiter.backoff_429 — same per-item retry pattern as
# Sync::UpdateRooms's department fallback).
#
# UPSERT, no diff: unlike characteristics (a room can have many, added/
# removed independently), a room has at most ONE RoomContact (`has_one`,
# unique room_id — phase 1). #sync_contact builds it if it doesn't exist yet
# and assigns every scheduling_*/support_* attribute wholesale from the
# response — there is nothing to diff, only fields to overwrite. A room
# whose response has no contact entry at all is left alone (no RoomContact
# created) rather than forced into existence with all-nil fields; there is
# nothing there worth persisting.
#
# Single "updated" counter (Brief §6.1 phase 6), not created/updated the way
# Sync::UpdateRooms distinguishes them: this phase never creates a Room, so
# there's no parallel "how many rows did this feed add to the table"
# question the way there is for rooms/buildings/campuses — it either wrote a
# room's contact block or it didn't, and `count(:updated) if contact.
# changed_after_assign(attrs)` (the same idiom Sync::UpdateFacilityIds uses)
# reports that uniformly whether the RoomContact was brand new or already on
# file.
#
# "" -> nil coercion, and space-padded values (sync-fix-decisions.md Risk 1,
# live-confirmed 2026-07-10): the real gateway sends every field
# space-padded when empty (`" "`, not `""` or JSON `null`) — #parse_contact
# therefore calls `.to_s.strip.presence` on every field, not a bare
# `.presence`: `.to_s` tolerates a JSON `null` (already nil, `.to_s` -> `""`),
# `.strip` collapses the space-padding to `""`, and `.presence` turns that
# `""` into `nil` — never storing a blank or whitespace-only string either
# way.
#
# parse_contact(row) / contacts_from(body) isolation: per spec/support/
# um_api_stubs.rb's fixture-shape disclaimer, these are the ONLY two places
# that reach into a raw API response hash directly. `ContactName`/`Email`/
# `Phone`/`ScheduleURL`/`UsageGuideLinesURL`/`SpptDeptID`/`SpptCntctEmail`/
# `SpptCntctPhone`/`SpptCntctURL` (parse_contact) and the "Classrooms" ->
# "Classroom" envelope (contacts_from) are LIVE-CONFIRMED
# (sync-fix-decisions.md Risk 1, 2026-07-10) against the real gateway — the
# highest-uncertainty phase in the original sync-fix plan, now resolved.
# `support_department_description` has no source field in the real feed at
# all and is always nil.
#
# Endpoint path ("/aa/ClassroomList/v2/Classrooms"): confirmed against live
# credentialed access (sync-fix Task 4) — replaces the earlier best-effort
# guess ("/bf/Buildings/v2/Classrooms"); the "Contacts" sub-resource segment
# is unchanged.
module Sync
  class UpdateContacts < BasePhase
    KEY = "contacts"

    CLASSROOMS_PATH = "/aa/ClassroomList/v2/Classrooms"

    private

    def perform
      Room.for_current_workspace.where.not(facility_code: nil).find_each do |room|
        sync_contact(room)
      end
    end

    def contacts_path(facility_code) = "#{CLASSROOMS_PATH}/#{ERB::Util.url_encode(facility_code)}/Contacts"

    def sync_contact(room)
      row = fetch_contact(room)
      return unless row

      attrs = parse_contact(row)
      contact = room.room_contact || room.build_room_contact(workspace: room.workspace)
      count(:updated) if contact.changed_after_assign(attrs)
      contact.save!
    end

    def fetch_contact(room)
      body = client.rate_limiter.backoff_429 do
        client.get_json(contacts_path(room.facility_code), scope: "classrooms")
      end
      contacts_from(body).first
    end

    # Single documented raw-access point for the response envelope's shape —
    # see header comment. If a future cutover finds the envelope shaped
    # differently, only this method needs to change.
    def contacts_from(body) = body.dig("Classrooms", "Classroom") || []

    def parse_contact(row)
      {
        scheduling_name: row["ContactName"].to_s.strip.presence,
        scheduling_email: row["Email"].to_s.strip.presence,
        scheduling_phone: row["Phone"].to_s.strip.presence,
        scheduling_detail_url: row["ScheduleURL"].to_s.strip.presence,
        scheduling_usage_guidelines_url: row["UsageGuideLinesURL"].to_s.strip.presence,
        support_department_id: row["SpptDeptID"].to_s.strip.presence,
        support_department_description: nil,
        support_email: row["SpptCntctEmail"].to_s.strip.presence,
        support_phone: row["SpptCntctPhone"].to_s.strip.presence,
        support_url: row["SpptCntctURL"].to_s.strip.presence
      }
    end
  end
end
