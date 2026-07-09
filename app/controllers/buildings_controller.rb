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
    scope = scope.merge(Building.search_name(params[:q])) if params[:q].present?

    # includes(:campus): both the HTML table and building_summary_json read
    # building.campus&.description per row — without this, Bullet (raise =
    # true in test) flags an N+1 the moment a second building renders.
    @pagy, @buildings = pagy(scope.order(:name).includes(:campus))

    respond_to do |format|
      format.html
      format.json { render json: index_json }
    end
  end

  def show
    authorize @building

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
      classroom_count: building.rooms.classroom.count,
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
      # includes(plan_attachment: :blob): floor_json's blob_url reads
      # floor.plan.attached? (needs plan_attachment) and, when attached,
      # rails_blob_url (needs the blob too) per floor — Bullet flags both
      # halves as separate N+1s across more than one floor without this.
      floors: @building.floors.order(:label).includes(plan_attachment: :blob)
                       .map { |floor| floor_json(floor) }
    }
  end

  def floor_json(floor)
    {
      id: floor.id,
      label: floor.label,
      plan_url: blob_url(floor.plan),
      classroom_count: floor.rooms.classroom.count
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
