module Sync
  class UpdateFacilityIds < BasePhase
    KEY = "facility_ids"

    FACILITY_LIST_PATH = "/aa/ClassroomList/v2/Classrooms"

    private

    def perform
      seen = []
      skipped_rmrecnbrs = Set.new
      facility_ids_by_building = preload_facility_ids_by_building

      facility_ids = Building.for_current_workspace.order(:id).pluck(:bldrecnbr).flat_map { facility_ids_by_building[it] || [] }
      progress_total!(facility_ids.size)
      facility_ids.each do |facility_id|
        apply_facility(facility_id, seen, skipped_rmrecnbrs)
        progress!
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
        client.get_json("#{FACILITY_LIST_PATH}/#{ERB::Util.url_encode(facility_id)}/Characteristics", scope: "classrooms", remember: true)
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
