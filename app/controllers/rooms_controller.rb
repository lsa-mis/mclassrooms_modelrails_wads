# MiClassrooms Phase 3 Task 4 (Brief §5.2, §3.2): Find a Room's controller —
# wires RoomSearch (Task 2), CharacteristicFilterGroups (Task 3), and
# RoomPolicy (Task 1) into one endpoint. HTML and JSON share the same
# @search/@pagy/@rooms — the view (Task 5) renders cards, the JSON is the
# API shape consumed by future room-detail linking.
class RoomsController < ApplicationController
  include DirectoryScoped

  VIEWS = %w[active inactive_rooms inactive_buildings].freeze

  # REQUIRED CORRECTION vs. the phase-4 Task 3 brief: the brief's snippet lists
  # `only: [:show, :edit, :update, :floor_plan]`, anticipating the full action
  # set this controller will have by the end of the phase. But `:edit`/`:update`
  # (Task 7) and `:floor_plan` (Task 6) aren't defined as controller methods
  # yet, and `config.action_controller.raise_on_missing_callback_actions` is
  # `true` in both development.rb and test.rb (Rails 7.1+ default) — so a
  # before_action `only:` naming an undefined action isn't inert, it's a hard
  # `AbstractController::ActionNotFound` ("Unknown action") raised for EVERY
  # request to this controller, including `#index` (verified: it broke all 19
  # pre-existing Find-a-Room examples). Scoped to `:show` only for this task;
  # Tasks 6/7 must add `:floor_plan`/`:edit`/`:update` back to these lists in
  # the same commit that defines those methods.
  before_action :set_room, only: [ :show ]
  before_action :redirect_inactive_for_non_admins, only: [ :show ]

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

  # MiClassrooms Phase 4 Task 3 (Brief §5.3): room detail, HTML + JSON.
  # `RoomPresenter` (Task 2) supplies both the view-model chips/grouping and
  # the JSON payload — this action just wires policy + conditional GET around
  # it. `app/views/rooms/show.html.erb` itself ships in Task 4; the format.html
  # branch is wired now per the contract so Task 4 only has to add the template.
  def show
    authorize @room
    @presenter = RoomPresenter.new(@room, url: room_url(@room))

    # D14: conditional GET over room + contact + notes (own and building's) + all
    # media attachments. Cache-Control stays Rails-default `private, max-age=0,
    # must-revalidate` — the legacy no-store header is deliberately NOT set.
    # Admin-ness is in the ETag: admins see the inactive banner and edit controls.
    if stale?(etag: show_cache_key, last_modified: show_last_modified)
      respond_to do |format|
        format.html
        format.json { render json: @presenter.as_json }
      end
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

  # D14 ETag components: the room + its contact record (both attribute-level
  # changes), admin-ness (admins get the inactive banner/edit affordances —
  # a distinct cache entry per role), and the max updated_at across notes
  # (own + the building's, since the show page renders both) and every media
  # attachment. `@room` and `@room.room_contact` are ActiveRecord objects, so
  # Rails' combine_etags digests their cache_key (class + id + updated_at) —
  # a `room_contact` update alone (no `Room#updated_at` bump) still busts it.
  #
  # REQUIRED CORRECTION vs. the brief: `media_attachments.maximum(:updated_at)`
  # raises `SQLite3::SQLException: no such column: updated_at` —
  # `active_storage_attachments` (db/schema.rb) has only `created_at`, not
  # `updated_at`; attachment rows are immutable (attach/detach creates or
  # destroys a row rather than updating one in place), so `created_at` is not
  # just the fix but the semantically correct column: a newly-attached photo
  # or gallery image is a brand-new row whose `created_at` bumps the max.
  def show_cache_key
    [ @room, @room.room_contact, RoleResolver.for(Current.user).admin?,
      @room.notes.maximum(:updated_at), @room.building.notes.maximum(:updated_at),
      media_attachments.maximum(:created_at) ]
  end

  def show_last_modified
    [ @room.updated_at, @room.notes.maximum(:updated_at),
      @room.building.notes.maximum(:updated_at),
      media_attachments.maximum(:created_at) ].compact.max
  end

  # Every attachment the show page can render: the room's own has_one_attached
  # trio (photo/panorama/seating_chart — all `record_type: "Room"`) plus each
  # gallery image's attached `image` (`record_type: "RoomGalleryImage"`).
  def media_attachments
    ActiveStorage::Attachment.where(record_type: "Room", record_id: @room.id)
      .or(ActiveStorage::Attachment.where(record_type: "RoomGalleryImage", record_id: @room.gallery_image_ids))
  end

  def set_room
    # for_current_workspace keeps tenant isolation (CLAUDE.md deviation #1: no
    # unscoped `Room.find`) but does NOT filter by listed/hidden, so hidden
    # rooms stay findable here for the inactive-redirect/admin-banner logic
    # below.
    @room = Room.for_current_workspace.find(params[:id])
  end

  def redirect_inactive_for_non_admins
    return unless @room.hidden?
    return if RoleResolver.for(Current.user).admin?
    redirect_to find_a_room_path, notice: t("rooms.inactive_notice")
  end
end
