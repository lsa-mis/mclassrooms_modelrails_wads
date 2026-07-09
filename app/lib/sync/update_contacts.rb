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
# "" -> nil coercion (never store an empty string): #parse_contact calls
# `.presence` on every field pulled from the response. contacts_MLB1200.json
# already demonstrates the gateway sending a JSON `null` for an absent field
# (SupportPhone), which JSON.parse already turns into a Ruby nil;
# contacts_AH0100.json additionally sends an explicit "" and omits several
# keys entirely — `.presence` handles all three shapes ("" -> nil, JSON null
# -> already nil -> nil, missing key -> nil -> nil) with one call.
#
# parse_contact(row) isolation: per spec/support/um_api_stubs.rb's
# fixture-shape disclaimer, SchedName/SchedEmail/SchedPhone/SchedDetailUrl/
# SchedUsageGuidelinesUrl/SupportDeptId/SupportDeptDescr/SupportEmail/
# SupportPhone/SupportUrl match spec/fixtures/um_api/contacts_MLB1200.json
# exactly, NOT verified against credentialed access — if phase 8's cutover
# finds different field names, only this method needs to change.
#
# Endpoint path ("/bf/Buildings/v2/Classrooms/{facility_code}/Contacts"):
# mirrors Sync::UpdateCharacteristics's own per-classroom nesting off the
# same "/bf/Buildings/v2/Classrooms" parent — a best-effort guess pending
# phase 8's credentialed cutover, like every other phase's path constants.
module Sync
  class UpdateContacts < BasePhase
    KEY = "contacts"

    CLASSROOMS_PATH = "/bf/Buildings/v2/Classrooms"

    private

    def perform
      Room.for_current_workspace.where.not(facility_code: nil).find_each do |room|
        sync_contact(room)
      end
    end

    def contacts_path(facility_code) = "#{CLASSROOMS_PATH}/#{facility_code}/Contacts"

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
      body.fetch("Contacts", []).first
    end

    def parse_contact(row)
      {
        scheduling_name: row["SchedName"].presence,
        scheduling_email: row["SchedEmail"].presence,
        scheduling_phone: row["SchedPhone"].presence,
        scheduling_detail_url: row["SchedDetailUrl"].presence,
        scheduling_usage_guidelines_url: row["SchedUsageGuidelinesUrl"].presence,
        support_department_id: row["SupportDeptId"].presence,
        support_department_description: row["SupportDeptDescr"].presence,
        support_email: row["SupportEmail"].presence,
        support_phone: row["SupportPhone"].presence,
        support_url: row["SupportUrl"].presence
      }
    end
  end
end
