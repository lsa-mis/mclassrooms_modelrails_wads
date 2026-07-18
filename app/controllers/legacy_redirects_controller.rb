class LegacyRedirectsController < ApplicationController
  include DirectoryScoped

  # Old-app deep links arrive signed out; each destination enforces its own auth.
  allow_unauthenticated_access

  # LSA's DeptGrp code as delivered by the U-M Department API (D5) — the Unit
  # NATURAL KEY, not its description. Confirm against live synced data before
  # cutover; a mismatch degrades gracefully (plain Find a Room, no LSA filter).
  LSA_DEPARTMENT_GROUP = "COLLEGE_OF_LSA".freeze

  # /classrooms/:facility_code -> the room. 302 (not 301): a code unknown today
  # may resolve after a later sync, so the redirect must stay dynamic.
  def room
    room = Room.for_current_workspace.find_by_facility_code(params[:facility_code])
    if room
      redirect_to room_path(room), notice: t("legacy_redirects.outdated_link")
    else
      redirect_to find_a_room_path, alert: t("legacy_redirects.unknown_code")
    end
  end

  # /classrooms -> Find a Room, pre-filtered to LSA (the old app was LSA-only).
  def classrooms_index
    lsa = Unit.for_current_workspace.find_by(department_group: LSA_DEPARTMENT_GROUP)
    redirect_to find_a_room_path(lsa ? { unit_id: lsa.id } : {}), status: :moved_permanently
  end

  # /legacy_crdb -> the retired LSA classroom database's own host.
  def legacy_crdb
    redirect_to "https://rooms.lsa.umich.edu", allow_other_host: true, status: :moved_permanently
  end

  # /toggle_visibile/:id — old GET toggled visibility; hide/unhide are POSTs now,
  # and old links carry rmrecnbr (contradiction #2). Land on the curation surface
  # (the room's edit page) where hide/unhide lives instead of replaying a mutation.
  def toggle_visibility
    room = Room.for_current_workspace.find_by(rmrecnbr: params[:id])
    if room
      redirect_to edit_room_path(room), notice: t("legacy_redirects.visibility_moved")
    else
      redirect_to find_a_room_path, alert: t("legacy_redirects.unknown_code")
    end
  end
end
