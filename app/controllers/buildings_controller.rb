# MiClassrooms Phase 4 Task 8 (Brief §5.3, §14.1): the admin Buildings
# section — index (FTS5 search over name/nickname/abbreviation, hidden
# toggle, pagination) and show (floors + read-only notes). Every action is
# admin-only (BuildingPolicy). HTML and JSON share the same @buildings/@pagy
# (index) or @building (show).
class BuildingsController < ApplicationController
  include DirectoryScoped

  # Task 9 extends this to `only: [:show, :edit, :update]` once #edit/#update
  # are real controller methods. `resources :buildings, only: [:index, :show,
  # :edit, :update]` is already drawn per the route contract (config/routes/
  # app.rb), but naming an undefined action in a before_action's `only:` list
  # raises AbstractController::ActionNotFound on EVERY request —
  # raise_on_missing_callback_actions is true in dev/test (see
  # config/environments/{development,test}.rb) — #index included. Mirrors
  # RoomsController's identical constraint before Task 7 added #edit/#update
  # there.
  before_action :set_building, only: [ :show ]

  # Admin-only page (BuildingPolicy#index?), so `show_hidden=1` needs no
  # extra gate beyond the action-level `authorize` below — there is no
  # narrower "safe" scope to fall back to the way RoomPolicy::Scope#resolve
  # is the safe default for a non-admin `view=inactive_rooms` request.
  def index
    authorize Building
    scope = BuildingPolicy::Scope.new(pundit_user, Building).resolve
    scope = scope.listed unless params[:show_hidden] == "1"
    # `.where(id: ...)` (not `.merge`): both `with_classrooms` (from the
    # policy Scope) and `Building.search_name` filter on the SAME `id`
    # column via `where(id: ...)`. `Relation#merge` overrides — not ANDs — a
    # duplicate equality/IN predicate on the merging side, so `.merge` here
    # would silently discard `with_classrooms` whenever `q` is present and
    # leak a classroom-less building whose name/nickname/abbreviation
    # matches the term. Chaining `.where` always ANDs, regardless of column
    # collisions, which is what we want: both conditions must hold.
    scope = scope.where(id: Building.search_name(params[:q])) if params[:q].present?

    # includes(:campus): both the HTML table and building_summary_json read
    # building.campus&.description per row — without this, Bullet (raise =
    # true in test) flags an N+1 the moment a second building renders.
    @pagy, @buildings = pagy(scope.order(:name).includes(:campus))

    # Grouped COUNT computed ONCE for the whole page, not a fresh
    # `building.rooms.classroom.count` query per row. Bullet doesn't catch
    # this — it's a further-scoped `.count`/aggregate on a loaded record, not
    # an unpreloaded association lazy-load — so this slipped past the green
    # Bullet run. Both the HTML view and building_summary_json read this
    # same Hash via `#fetch(building.id, 0)`.
    @classroom_counts = Room.classroom.where(building_id: @buildings.map(&:id)).group(:building_id).count

    respond_to do |format|
      format.html
      format.json { render json: index_json }
    end
  end

  def show
    authorize @building

    # Loaded ONCE here — the view previously re-queried `@building.floors`
    # from scratch (without this `includes`) instead of reusing show_json's
    # preloaded collection, so `floor.plan.attached?` fired a fresh query per
    # floor in the HTML render. `includes(plan_attachment: :blob)` lets both
    # the view and show_json read the same preloaded association.
    @floors = @building.floors.order(:label).includes(plan_attachment: :blob)
    floor_ids = @floors.map(&:id) # forces the load now, so `@floors.any?` in the view reuses it for free

    # Same batching as @classroom_counts above, scoped to floors instead of
    # buildings — replaces a `floor.rooms.classroom.count` query per floor.
    @floor_classroom_counts = Room.classroom.where(floor_id: floor_ids).group(:floor_id).count

    # Representative classroom per floor (for the floor-plan link), loaded in
    # ONE query and grouped in Ruby instead of `floor.rooms.classroom.order(:id).first`
    # per floor. `order(:floor_id, :id)` keeps each floor's own rooms in `:id`
    # order so `#first` on the grouped array matches the old per-floor query.
    @floor_representative_rooms = Room.classroom.where(floor_id: floor_ids).order(:floor_id, :id).group_by(&:floor_id)

    respond_to do |format|
      format.html
      format.json { render json: show_json }
    end
  end

  private

  def set_building
    # for_current_workspace (CLAUDE.md deviation #1): tenant-scoped find,
    # never a bare Building.find — mirrors RoomsController#set_room. Not
    # `.listed`-filtered: this is the admin page, so a hidden building must
    # still be reachable by id.
    @building = Building.for_current_workspace.find(params[:id])
  end

  def index_json
    {
      buildings: @buildings.map { |building| building_summary_json(building) },
      page: @pagy.page,
      pages: @pagy.pages
    }
  end

  def building_summary_json(building)
    {
      id: building.id,
      bldrecnbr: building.bldrecnbr,
      name: building.name,
      nickname: building.nickname,
      abbreviation: building.abbreviation,
      campus: building.campus&.description,
      classroom_count: @classroom_counts.fetch(building.id, 0),
      hidden: building.hidden?
    }
  end

  def show_json
    {
      id: @building.id,
      bldrecnbr: @building.bldrecnbr,
      name: @building.name,
      nickname: @building.nickname,
      abbreviation: @building.abbreviation,
      campus: @building.campus&.description,
      hidden: @building.hidden?,
      address: @building.address,
      city: @building.city,
      state: @building.state,
      zip: @building.zip,
      country: @building.country,
      full_address: @building.full_address,
      photo_url: blob_url(@building.photo),
      # @floors: the SAME preloaded (plan_attachment: :blob) collection the
      # #show action built — not a re-query — so floor_json's blob_url
      # (floor.plan.attached?, then rails_blob_url) never fires per-floor SQL.
      floors: @floors.map { |floor| floor_json(floor) }
    }
  end

  def floor_json(floor)
    {
      id: floor.id,
      label: floor.label,
      plan_url: blob_url(floor.plan),
      classroom_count: @floor_classroom_counts.fetch(floor.id, 0)
    }
  end

  # Mirrors RoomPresenter#blob_url (app/lib/room_presenter.rb): nil for an
  # unattached has_one_attached, a full rails_blob_url otherwise. Called from
  # a controller (not a view/presenter), so `rails_blob_url` resolves via
  # ActionController's own routes.url_helpers inclusion.
  def blob_url(attachment)
    return nil unless attachment.attached?

    rails_blob_url(attachment)
  end
end
