# MiClassrooms Phase 3 Task 4 (Brief §5.2, §3.2): Find a Room's controller —
# wires RoomSearch (Task 2), CharacteristicFilterGroups (Task 3), and
# RoomPolicy (Task 1) into one endpoint. HTML and JSON share the same
# @search/@pagy/@rooms — the view (Task 5) renders cards, the JSON is the
# API shape consumed by future room-detail linking.
class RoomsController < ApplicationController
  include DirectoryScoped
  include PublicDirectoryChrome
  include RoomEditPage

  VIEWS = %w[active inactive_rooms inactive_buildings].freeze

  CURATED_PARAMS = [ :nickname, :ada_seat_count ].freeze

  # Task 7 (Brief §5.3) now defines #edit/#update below, so both actions join
  # set_room — the phase-4 Task 3 brief's originally-anticipated
  # `only: [:show, :edit, :update, :floor_plan]` couldn't be written until
  # #edit/#update existed as real methods (raise_on_missing_callback_actions
  # is `true` in dev/test, so naming an undefined action here raises
  # AbstractController::ActionNotFound for every request, #index included).
  # redirect_inactive_for_non_admins deliberately stays scoped to
  # :show/:floor_plan only: an admin editing a HIDDEN room is the normal path
  # (how else would they un-hide one?), and a non-admin never reaches
  # #edit/#update at all — RoomPolicy#edit?/#update? deny them via `authorize`
  # below, the same redirect-with-alert as every other Pundit denial in this
  # app.
  before_action :set_room, only: [ :show, :edit, :update ]
  before_action :redirect_inactive_for_non_admins, only: [ :show ]

  def index
    authorize Room
    @filter_params = filter_params
    @search = RoomSearch.new(@filter_params, base: base_scope, saved_for: Current.user)
    @pagy, @rooms = pagy(:offset, @search.results, limit: @search.per_page)
    @filter_groups = CharacteristicFilterGroups.filters
    # Per-room note/alert counts for the result cards in ONE grouped query
    # (rendering bodies per card would N+1 Action Text; counts are enough —
    # the full live notes surface lives on the room page). Roots only, so
    # threaded replies don't inflate the count.
    @note_stats = Note.roots.where(notable_type: "Room", notable_id: @rooms.map(&:id))
                      .group(:notable_id, :alert).count
    # Shortlist state for the cards + header count — two small queries, no N+1.
    @saved_room_ids = Current.user.saved_rooms.where(room_id: @rooms.map(&:id)).pluck(:room_id, :id).to_h
    @saved_count = Current.user.saved_rooms.where(workspace: Current.workspace).count
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
    @saved_id = Current.user.saved_rooms.find_by(room_id: @room.id)&.id

    # D14: conditional GET over room + contact + notes (own and building's) + all
    # media attachments. Cache-Control stays Rails-default `private, max-age=0,
    # must-revalidate` — the legacy no-store header is deliberately NOT set.
    # Admin-ness is in the ETag: admins see the inactive banner and edit controls.
    if stale?(etag: show_cache_key, last_modified: show_last_modified)
      respond_to do |format|
        format.html
        format.json do
          # media_json walks asset.image per gallery row and @room came from
          # set_room's plain find — with 2+ assets that's an image_attachment
          # N+1 (Bullet raises). Same in-memory Preloader helper #edit/#update
          # use; scoped to the JSON branch so a 304 never carries an unused
          # eager load.
          preload_gallery_image_attachments
          render json: @presenter.as_json
        end
      end
    end
  end

  def edit
    authorize @room
    prepare_edit_page(open_media: params[:open].presence_in(%w[panorama seating_chart gallery])&.to_sym)
  end

  def update
    authorize @room
    result = apply_curated_change(room_params.to_h)

    if result.nil? || result.success?
      redirect_to room_path(@room), notice: t("rooms.edit.success")
    else
      @room = result.payload[:record] || @room
      render_edit_failure(nil)
    end
  end

  private

  def apply_curated_change(curated_attrs)
    return nil if curated_attrs.blank?

    @room.assign_attributes(curated_attrs)
    return nil unless @room.changed?

    Curation::Apply.call(record: @room, actor: Current.user, action: "room.updated")
  end

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

  # `q` is the redesign's merged search box; `building`/`room` stay permitted
  # for shared pre-redesign URLs (RoomSearch still honors them).
  def filter_params
    params.permit(:q, :building, :room, :unit_id, :capacity_min, :capacity_max,
                  :sort, :per, :view, :saved, characteristics: [])
  end

  def room_params
    params.expect(room: CURATED_PARAMS)
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
  # just the fix but the semantically correct column: a newly-attached panorama
  # or gallery image is a brand-new row whose `created_at` bumps the max.
  def show_cache_key
    # @saved_id is per-user save state rendered on the page — it must bust
    # the conditional-GET cache like admin-ness does.
    [ @room, @room.room_contact, RoleResolver.for(Current.user).admin?, @saved_id,
      @room.notes.maximum(:updated_at), @room.building.notes.maximum(:updated_at),
      media_attachments.maximum(:created_at) ]
  end

  def show_last_modified
    [ @room.updated_at, @room.notes.maximum(:updated_at),
      @room.building.notes.maximum(:updated_at),
      media_attachments.maximum(:created_at) ].compact.max
  end

  # Every attachment the show page can render: the room's own has_one_attached
  # slots (panorama/flat_panorama/seating_chart — all `record_type: "Room"`)
  # plus each gallery asset's attached `image`. The gallery half is keyed off
  # `MediaAsset.name` rather than a string literal deliberately: this query
  # fails SILENTLY (an empty `.or` branch, a stale ETag, a page that never
  # revalidates) rather than raising, so a future rename must break the
  # constant, not quietly stop matching.
  def media_attachments
    ActiveStorage::Attachment.where(record_type: "Room", record_id: @room.id)
      .or(ActiveStorage::Attachment.where(record_type: MediaAsset.name, record_id: @room.gallery_ids))
  end

  def set_room
    # Look up by rmrecnbr — the URL param (see Room#to_param) — scoped through
    # for_current_workspace to keep tenant isolation (CLAUDE.md deviation #1: no
    # unscoped `Room.find`). Does NOT filter by listed/hidden, so hidden rooms
    # stay findable here for the inactive-redirect/admin-banner logic below.
    @room = Room.for_current_workspace.find_by!(rmrecnbr: params[:id])
  rescue ActiveRecord::RecordNotFound
    # A shared or stale room link (unknown rmrecnbr, or a room in another
    # workspace) should land on the room directory with a clear message — not
    # the app's generic RecordNotFound handler, which redirects to the marketing
    # home (2026-07-15 panel: a shared *room* link deserves a room-shaped miss).
    # redirect_to in a before_action halts the filter chain.
    redirect_to find_a_room_path, alert: t("rooms.show.not_found")
  end

  def redirect_inactive_for_non_admins
    return unless @room.hidden?
    return if RoleResolver.for(Current.user).admin?
    redirect_to find_a_room_path, notice: t("rooms.inactive_notice")
  end
end
