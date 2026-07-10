# MiClassrooms Phase 4 Task 8 (Brief §5.3, §14.1): the admin Buildings
# section — index (FTS5 search over name/nickname/abbreviation, hidden
# toggle, pagination) and show (floors + read-only notes). Every action is
# admin-only (BuildingPolicy). HTML and JSON share the same @buildings/@pagy
# (index) or @building (show).
class BuildingsController < ApplicationController
  include DirectoryScoped

  # Extended to `:edit, :update` now that both are real controller methods
  # (Task 9). `resources :buildings, only: [:index, :show, :edit, :update]`
  # was already drawn per the route contract (config/routes/app.rb) ahead of
  # this — naming an undefined action in a before_action's `only:` list
  # raises AbstractController::ActionNotFound on EVERY request (dev/test set
  # raise_on_missing_callback_actions: true), which is why #edit/#update
  # couldn't join this list until they existed. Mirrors RoomsController's
  # identical `set_room` extension in its own Task 7.
  #
  # Phase 5 Task 5: `:hide, :unhide` join for the same reason — both actions
  # need @building loaded to authorize/mutate.
  before_action :set_building, only: [ :show, :edit, :update, :hide, :unhide ]

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

  # MiClassrooms Phase 4 Task 9 (Brief §5.3, §14.1): the admin building edit
  # form — nickname + photo (curated fields) plus per-floor floor-plan
  # attach/replace/remove via nested attributes. Mirrors RoomsController#edit
  # (Task 7): `authorize @building` only, then preload each floor's `plan`
  # attachment so the view's per-floor `floor.plan.attached?`/content_type
  # checks don't N+1 (Bullet raises in test).
  def edit
    authorize @building
    load_floors
  end

  # Routes the whole payload — nickname, photo (+ remove_photo), and each
  # floor's plan (+ remove_plan) — through Curation::Apply.call in ONE
  # transaction (spec D13), exactly like RoomsController#update. Attachment
  # operations aren't dirty-tracked, so their before_after diff is empty —
  # the "building.curated" action string is their audit signal; a genuine
  # column change (nickname) still appears in the diff normally.
  def update
    authorize @building
    attrs = building_params.to_h

    # Guard BEFORE Curation::Apply ever sees `attrs`: Rails' own
    # `assign_nested_attributes_for_collection_association` resolves each
    # row's `:id` against `association.scope.where(id: ...)` (i.e.
    # `@building.floors` scoped to THIS building) — a row whose `:id`
    # belongs to another building's floor, or a floor the nightly sync
    # removed between this page's load and this submit, finds nothing there
    # and calls `raise_nested_attributes_record_not_found!`, raising
    # ActiveRecord::RecordNotFound from INSIDE
    # `@record.assign_attributes(@attributes)` — i.e. before
    # Curation::Apply's transaction (and its RecordInvalid/
    # RecordNotDestroyed rescue) even opens. Left unguarded,
    # ApplicationController's blanket `rescue_from ActiveRecord::RecordNotFound`
    # catches it globally and (for an HTML request) redirects to
    # `request.referer || root_path` with a generic "not found" alert —
    # bouncing an otherwise-valid admin edit off the edit page entirely,
    # not the documented graceful 422 re-render. Checking every submitted id
    # against `@building.floor_ids` up front means a bad id never reaches
    # `assign_attributes` at all.
    if stale_floor_ids?(attrs)
      load_floors
      flash.now[:alert] = t("buildings.edit.stale_floor")
      render :edit, status: :unprocessable_entity
      return
    end

    # Preloaded BEFORE Curation::Apply.call, not just before a failure
    # re-render: a floor RECEIVING A NEW plan upload is the one case
    # Building#save!'s autosave cascade actually (re-)validates this
    # request — remove_plan alone or an untouched floor (skipped by
    # Building#floors' reject_if) never registers as `changed_for_autosave?`
    # (see this method's own comment), so preloading every floor
    # unconditionally flagged Bullet's OWN "unused eager loading" check on
    # the remove-only path. Scoping the preload to just the touched
    # floor(s) satisfies both directions. Mirrors RoomsController#update's
    # `preload_gallery_image_attachments` call before its own
    # Curation::Apply.call.
    preload_new_floor_plan_attachments(attrs)
    result = Curation::Apply.call(record: @building, actor: Current.user,
                                  attributes: attrs, action: "building.curated")

    if result.success?
      redirect_to building_path(@building), notice: t("buildings.edit.success")
    else
      @building = result.payload[:record] || @building
      load_floors
      render :edit, status: :unprocessable_entity
    end
  end

  # Phase 5 Task 5 (Brief §14.1): admin-only hide/unhide — BuildingPolicy
  # #hide?/#unhide? are both `grant.admin?`, so unlike RoomsController#hide
  # there's no editor grantee to route away from the record; `policy(
  # @building).show?` is always true immediately after an admin hides one
  # (BuildingPolicy#show? admits `grant.admin?` unconditionally), so the
  # ternary mirrors RoomsController#hide's shape for consistency even though
  # its "else" branch is unreachable under the current policy.
  def hide
    authorize @building, :hide?
    @building.hide!(actor: Current.user)
    redirect_to policy(@building).show? ? building_path(@building) : buildings_path,
                notice: t("buildings.hide.success")
  end

  def unhide
    authorize @building, :unhide?
    @building.unhide!(actor: Current.user)
    redirect_to building_path(@building), notice: t("buildings.unhide.success")
  end

  private

  # Preloads each floor's `plan` attachment (mirrors #show's identical
  # `includes(plan_attachment: :blob)`) so #edit's first render AND #update's
  # failure re-render both avoid an N+1 across the floors card's per-floor
  # plan.attached?/content_type checks.
  def load_floors
    @floors = @building.floors.order(:label).includes(plan_attachment: :blob)
  end

  # Preloads the `plan` attachment ONLY for the floor(s) whose submitted
  # attributes include a NEW `plan` upload — the sole case where
  # Building#save!'s autosave cascade actually validates that Floor's `plan`
  # content type/size this request. `remove_plan` alone doesn't touch AR's
  # dirty-tracking or ActiveStorage's `attachment_changes` (purge_later just
  # schedules a job), so a remove-only or otherwise-untouched floor is never
  # `changed_for_autosave?` and its validations never run — preloading it
  # anyway is itself an UNUSED eager load Bullet flags just as readily as a
  # missing one. `@building.floors.select { ... }` (not a fresh `.includes`
  # query) loads the association's target ONTO `@building.floors` itself —
  # the same in-memory objects `floors_attributes=` is about to find and
  # mutate below — same technique as
  # RoomsController#preload_gallery_image_attachments.
  #
  # Both `plan_attachment: :blob` and the auto-generated `plan_blob`
  # shortcut (has_one_attached's own `has_one :plan_blob, through:
  # :plan_attachment`) need preloading: #show's read-only view only ever
  # touches the former, but ActiveStorageValidations::ContentTypeValidator
  # reads blob content type via the `plan_blob` shortcut directly — a
  # SEPARATE association Bullet tracks on its own.
  def preload_new_floor_plan_attachments(attrs)
    ids = floor_ids_with_new_plan(attrs)
    return if ids.empty?

    floors = @building.floors.select { |floor| ids.include?(floor.id.to_s) }
    return if floors.empty?

    ActiveRecord::Associations::Preloader.new(
      records: floors, associations: [ :plan_blob, { plan_attachment: :blob } ]
    ).call
  end

  # Ids of floors whose submitted nested-attribute row includes a present
  # `plan` (a real file upload) — see preload_new_floor_plan_attachments'
  # comment above and submitted_floor_rows' comment below for the row
  # extraction this delegates to.
  def floor_ids_with_new_plan(attrs)
    submitted_floor_rows(attrs).select { |row| row[:plan].present? }
                                .map { |row| row[:id].to_s }
                                .compact
  end

  # True when `floors_attributes` names an `:id` that is NOT one of
  # `@building`'s own floors — a foreign building's floor id, or a floor the
  # nightly sync deleted between this page's load and this submit. Compared
  # as strings (`floor_ids` are Integers, submitted ids are form strings) so
  # `"7" == 7` doesn't silently fail the `include?` check.
  def stale_floor_ids?(attrs)
    submitted_ids = submitted_floor_rows(attrs).map { |row| row[:id].to_s }.compact_blank
    return false if submitted_ids.empty?

    known_ids = @building.floor_ids.map(&:to_s)
    submitted_ids.any? { |id| known_ids.exclude?(id) }
  end

  # Shared row-extraction for both floor_ids_with_new_plan and
  # stale_floor_ids? — `building_params.to_h`'s nested floors_attributes hash
  # and its per-row hashes are both plain Hash by the time they reach here,
  # and Rails' own `fields_for` always submits this as a hash keyed by index
  # (never a bare array), but the defensive `Array(...)`/`.is_a?(Hash)`
  # branch (mirrors RoomsController#destroyed_gallery_image_ids) tolerates
  # either shape. Each returned row is already `.with_indifferent_access`'d
  # so callers can read `row[:id]`/`row[:plan]` directly.
  def submitted_floor_rows(attrs)
    rows = attrs.with_indifferent_access[:floors_attributes]
    return [] if rows.blank?

    rows = rows.is_a?(Hash) ? rows.values : Array(rows)
    rows.map(&:with_indifferent_access)
  end

  def set_building
    # for_current_workspace (CLAUDE.md deviation #1): tenant-scoped find,
    # never a bare Building.find — mirrors RoomsController#set_room. Not
    # `.listed`-filtered: this is the admin page, so a hidden building must
    # still be reachable by id.
    @building = Building.for_current_workspace.find(params[:id])
  end

  # Curated fields (nickname), the photo slot + its remove_photo purge
  # writer, and per-floor plan attach/replace/remove via nested attributes.
  #
  # DEVIATION (Decision 2): deliberately NO address fields (:address, :city,
  # :state, :zip, :country) and NO visibility params (:hidden_at, :in_feed)
  # here. Address is sync-owned (Brief §5.3/D6) — permitting it here would
  # let an admin's edit be silently overwritten by the next nightly sync, or
  # (worse) let a curated edit clobber sync data out of band. Visibility
  # (hide/unhide) ships with phase 5's dedicated routes, not this form. Any
  # `address`/`city`/`state`/`zip`/`country`/`hidden_at`/`in_feed` param
  # submitted here is silently dropped by strong params, never assigned.
  def building_params
    params.require(:building).permit(
      :nickname, :photo, :remove_photo,
      floors_attributes: [ :id, :plan, :remove_plan ]
    )
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
