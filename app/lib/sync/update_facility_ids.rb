module Sync
  class UpdateFacilityIds < BasePhase
    KEY = "facility_ids"

    FACILITY_LIST_PATH = "/aa/ClassroomList/v2/Classrooms"

    private

    def perform
      seen = []
      unread_facility_ids = []
      skipped_rmrecnbrs = Set.new
      facility_ids_by_building = preload_facility_ids_by_building

      facility_ids = Building.for_current_workspace.order(:id).pluck(:bldrecnbr).flat_map { facility_ids_by_building[it] || [] }
      progress_total!(facility_ids.size)
      facility_ids.each do |facility_id|
        apply_facility(facility_id, seen, unread_facility_ids, skipped_rmrecnbrs)
        progress!
      end

      clear_stale_facility_codes(seen, unread_facility_ids)
      Setting.recompute_capacity_filter_max!
    end

    def preload_facility_ids_by_building
      rows = client.rate_limiter.backoff_429 do
        client.fetch_all(FACILITY_LIST_PATH, array_path: %w[Classrooms Classroom], scope: "classrooms")
      end
      rows.group_by { |row| row["BuildingID"] }
          .transform_values { |group| group.map { |row| row["FacilityID"] }.uniq }
    end

    def apply_facility(facility_id, seen, unread_facility_ids, skipped_rmrecnbrs)
      rmrecnbrs = fetch_facility_characteristics(facility_id).filter_map { |row| row["RmRecNbr"].presence }.uniq
      unread_facility_ids << facility_id if rmrecnbrs.empty?

      rmrecnbrs.each do |rmrecnbr|
        seen << rmrecnbr
        upsert_facility_id(rmrecnbr, facility_id, skipped_rmrecnbrs)
      end
    end

    def fetch_facility_characteristics(facility_id)
      body = client.rate_limiter.backoff_429 do
        client.get_json("#{FACILITY_LIST_PATH}/#{ERB::Util.url_encode(facility_id)}/Characteristics", scope: "classrooms", remember: true)
      end
      body.dig("Classrooms", "Classroom") || []
    rescue UmApi::NotFound, UmApi::ServerError => e
      add_warning("Facility #{facility_id} characteristics fetch failed (#{e.class}); crosswalk discovery skipped for this facility")
      []
    end

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

    def clear_stale_facility_codes(seen, unread_facility_ids)
      if seen.empty?
        add_warning("Classroom facility crosswalk discovered zero rows this run; skipping facility_code clear sweep")
        return
      end

      stale = Room.for_current_workspace.where.not(facility_code: nil).where.not(rmrecnbr: seen)
                  .where.not(facility_code: unread_facility_ids)

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
