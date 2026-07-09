# MiClassrooms Phase 3 Task 4 (Brief §5.2, §3.2): Find a Room's controller —
# wires RoomSearch (Task 2), CharacteristicFilterGroups (Task 3), and
# RoomPolicy (Task 1) into one endpoint. HTML and JSON share the same
# @search/@pagy/@rooms — the view (Task 5) renders cards, the JSON is the
# API shape consumed by future room-detail linking.
class RoomsController < ApplicationController
  include DirectoryScoped

  VIEWS = %w[active inactive_rooms inactive_buildings].freeze

  def index
    authorize Room
    @search = RoomSearch.new(filter_params, base: base_scope)
    @pagy, @rooms = pagy(:offset, @search.results, limit: @search.per_page)
    @filter_groups = CharacteristicFilterGroups.filters
    # with_attached_photo (Rails' auto-generated has_one_attached scope) preloads
    # photo_attachment + blob for every building in one pass — `_building_card`
    # calls `building.photo.attached?` per card, which N+1s per building without
    # it (Task 8 system specs surfaced this: Bullet raises with 2+ buildings in
    # the results).
    @buildings = Building.where(id: @rooms.map(&:building_id).uniq).order(:name).with_attached_photo
    @announcement = Announcement.for(:find_a_room_page)
    respond_to do |format|
      format.html # never fresh_when here — D14: results are live queries
      format.json
    end
  end

  private

  def view = params[:view].presence_in(VIEWS) || "active"

  # Every branch routes through RoomPolicy::Scope rather than a bare
  # `Room.classroom` query, so workspace isolation (`for_current_workspace`)
  # and the admin-only widening rule stay centralized in the policy instead
  # of being re-derived here. `resolve_including_inactive` is NOT reachable
  # via Pundit's `policy_scope(Room)` helper (that always calls #resolve) —
  # it has to be instantiated directly, and only after the explicit
  # `view_inactive?` authorize call below, so a viewer/editor requesting
  # `view=inactive_rooms`/`inactive_buildings` is denied (Pundit::NotAuthorizedError,
  # rescued in ApplicationController) rather than silently served the safe scope.
  def base_scope
    case view
    when "inactive_rooms"
      authorize Room, :view_inactive?
      scope = RoomPolicy::Scope.new(pundit_user, Room).resolve_including_inactive
      scope.where.not(id: scope.listed.select(:id))
    when "inactive_buildings"
      authorize Room, :view_inactive?
      RoomPolicy::Scope.new(pundit_user, Room).resolve_including_inactive
        .where.not(building_id: Building.for_current_workspace.listed.select(:id))
    else
      RoomPolicy::Scope.new(pundit_user, Room).resolve
    end
  end

  def filter_params
    params.permit(:building, :room, :unit_id, :capacity_min, :capacity_max,
                  :sort, :per, :view, characteristics: [])
  end
end
