# MiClassrooms Phase 3 Task 4 (Brief §5.2, §3.2): Find a Room's controller —
# wires RoomSearch (Task 2), CharacteristicFilterGroups (Task 3), and
# RoomPolicy (Task 1) into one endpoint. HTML and JSON share the same
# @search/@pagy/@rooms — the view (Task 5) renders cards, the JSON is the
# API shape consumed by future room-detail linking.
class RoomsController < ApplicationController
  include DirectoryScoped

  VIEWS = %w[active inactive_rooms inactive_buildings].freeze

  # Phase 5 Task 6 (Brief §14.1): the authorization boundary for #update, NOT
  # merely a hidden-UI convenience — RoomPolicy#update? now admits a unit
  # editor (Task 3), but RoomPolicy#manage_media? stays admin-only, so strong
  # params themselves must branch. Without this, a unit editor crafting
  # `PATCH /rooms/:id` with a `photo` (or `gallery_images_attributes`, or any
  # `remove_*` purge writer) directly in the request body — bypassing the
  # edit view entirely — would have it silently assigned and saved, since
  # `authorize @room` alone only gates REACHING #update, not which attributes
  # it may set once there. `room_params` below is the actual enforcement
  # point: MEDIA_PARAMS is only concatenated in when
  # `policy(@room).manage_media?`, so an editor's request has every media key
  # stripped before it ever reaches Curation::Apply, regardless of what the
  # client submitted.
  CURATED_PARAMS = [ :nickname, :ada_seat_count ].freeze

  # Kept as its own constant (not folded into `room_params` directly) so the
  # curated/media split reads as a deliberate security boundary, not an
  # incidental grouping. `gallery_images_attributes` uses the DOUBLE-array
  # `[[ ... ]]` shape `params.expect` requires for a Hash-of-hashes nested
  # collection (what `fields_for`'s index-keyed submission actually is) — the
  # single-array `permit`-style shape silently returns an EMPTY
  # gallery_images_attributes under `expect` (verified empirically against
  # this app's Rails version; `permit` tolerates either shape, `expect` does
  # not). Getting this wrong would silently break every admin gallery
  # add/reorder/destroy while looking correct in a review of the params list.
  MEDIA_PARAMS = [
    :photo, :panorama, :seating_chart,
    :remove_photo, :remove_panorama, :remove_seating_chart,
    { gallery_images_attributes: [ [ :id, :image, :position, :_destroy ] ] }
  ].freeze

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
  #
  # Phase 5 Task 5: #hide/#unhide join set_room too (they need @room loaded
  # to authorize/mutate), but deliberately do NOT join
  # redirect_inactive_for_non_admins below — a hide POST acts on a room that
  # is, by definition, still visible when the request is issued (RoomPolicy
  # #hide? requires visible_record? for a non-admin editor), and an admin
  # unhiding a room is unhiding a currently-HIDDEN one on purpose. Neither
  # case should be intercepted by the hidden-room redirect the way a GET
  # /rooms/:id is.
  before_action :set_room, only: [ :show, :floor_plan, :edit, :update, :hide, :unhide ]
  before_action :redirect_inactive_for_non_admins, only: [ :show, :floor_plan ]

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

  # MiClassrooms Phase 4 Task 6 (Brief §5.3): the floor-plan view — authorizes
  # identically to #show (a floor plan is just another facet of room detail,
  # not a separately-gated resource) and reuses `set_room`/
  # `redirect_inactive_for_non_admins` (both already extended to `:floor_plan`
  # above) so a hidden room's non-admin redirect fires before this method ever
  # runs. `@room.floor` can be nil (Floor is `optional: true` on Room) — that's
  # not an error state, just a room the nightly sync never assigned a floor
  # to, so it redirects back to the room with a notice rather than 404ing or
  # rendering a floor-less page.
  def floor_plan
    authorize @room, :show?
    @floor = @room.floor
    return redirect_to(room_path(@room), notice: t("rooms.floor_plan.no_floor")) if @floor.nil?

    # for_current_workspace kept explicit here (CLAUDE.md deviation #1) even
    # though floor_id already transitively scopes to the workspace (a Floor
    # belongs to a Building in exactly one workspace) — consistent with how
    # every other Room query in this controller resolves through an explicit
    # tenant scope rather than relying on a transitive guarantee.
    @rooms_on_floor = Room.for_current_workspace.classroom.listed
                          .where(floor_id: @floor.id).natural_room_order
  end

  # MiClassrooms Phase 4 Task 7 (Brief §5.3, §14.1): the phase's first admin
  # mutation — curated fields (nickname, ADA seat count) plus media
  # attach/remove/reorder, all in one form. `RoomPolicy#edit?` is admin-only
  # this phase (see the policy file's phase-5 seam comment).
  def edit
    authorize @room
    build_blank_gallery_images
  end

  # Phase 5 Task 6 (Brief §14.1) retrofit: routes curated-field changes and
  # media changes through TWO SEPARATE Curation::Apply calls instead of
  # phase 4's single combined one, so the audit trail can tell them apart —
  # a "room.updated" row's `before_after` is a real column diff (nickname,
  # ada_seat_count), and a "room.media_updated" row marks that a media
  # operation happened even though attachment ops still produce an empty
  # diff (unchanged from phase 4). ACHIEVED GRANULARITY: curated-vs-media
  # split, the brief's documented "acceptable floor" — NOT full per-slot
  # (room.photo_attached / room.gallery_image_added / etc.). Per-slot would
  # need each attach/purge/gallery-row change to become its OWN
  # Curation::Apply block-form call, which conflicts with how gallery rows
  # are assigned here: `gallery_images_attributes=` mutates several
  # RoomGalleryImage rows (add/reorder/destroy) in one
  # `accepts_nested_attributes_for` cascade that only resolves — including
  # its own validations — inside the PARENT Room's single `save!`. Splitting
  # that cascade into independent per-row saves would mean either
  # re-deriving Rails' own nested-attributes resolution by hand (id lookup,
  # reject_if, allow_destroy) outside the association, or calling `save!` on
  # the parent multiple times per row — both a materially larger, riskier
  # rewrite than this task's scope justifies against the existing
  # stale-id/preload guards below (which stay keyed to the FULL submitted
  # payload either way). Only two DISTINCT operations are split here: the
  # curated (real-column) change and the "everything media" change (three
  # attachment slots + their remove_* writers + gallery nested attributes),
  # matching the strong-params boundary above.
  #
  # TRADE-OFF vs. phase 4: two Curation::Apply calls means TWO independent
  # transactions, not one — a curated change can commit while a subsequent
  # media validation failure rolls back only the media half (the nickname
  # save is not undone). Phase 4's single-call guarantee ("either both the
  # record change and its ActivityLog commit, or neither does") now holds
  # PER OPERATION, not per request. Explicitly accepted by the brief for this
  # granularity; flagged here and in the task report rather than silently
  # narrowed.
  #
  # Each half is SKIPPED entirely (no Curation::Apply call, no ActivityLog)
  # when that half has nothing to apply — see curated_change?/media_change?
  # below — so a no-op resubmission writes zero rows and a curated-only edit
  # writes exactly one ("room.updated"), per the task's audit contract.
  def update
    authorize @room
    attrs = room_params.to_h

    # Guard BEFORE either Curation::Apply call ever sees `attrs`: Rails' own
    # `assign_nested_attributes_for_collection_association` resolves each
    # row's `:id` against `association.scope.where(id: ...)` (i.e.
    # `@room.gallery_images` scoped to THIS room) — a row whose `:id`
    # belongs to another room's gallery image, or one destroyed between
    # this page's load and this submit, finds nothing there and calls
    # `raise_nested_attributes_record_not_found!`, raising
    # ActiveRecord::RecordNotFound from INSIDE
    # `@record.assign_attributes(@attributes)` — i.e. before
    # Curation::Apply's transaction (and its RecordInvalid/
    # RecordNotDestroyed rescue) even opens. Left unguarded,
    # ApplicationController's blanket `rescue_from ActiveRecord::RecordNotFound`
    # catches it globally and (for an HTML request) redirects to
    # `request.referer || root_path` with a generic "not found" alert —
    # bouncing an otherwise-valid admin edit off the edit page entirely,
    # not the documented graceful 422 re-render. Checking every submitted id
    # against `@room.gallery_image_ids` up front means a bad id never
    # reaches `assign_attributes` at all. Mirrors BuildingsController#update's
    # identical `stale_floor_ids?` guard for floors_attributes.
    if stale_gallery_ids?(attrs)
      build_blank_gallery_images
      flash.now[:alert] = t("rooms.edit.stale_gallery")
      render :edit, status: :unprocessable_entity
      return
    end

    # Preloaded BEFORE either Curation::Apply call, not just before a failure
    # re-render: a gallery reorder/destroy re-validates every SURVIVING
    # RoomGalleryImage's `attached: true` during the autosave cascade inside
    # the media Curation::Apply's `@record.save!` below, and @room came from
    # set_room's plain `find` (no gallery_images preload) — Bullet raises on
    # that N+1 regardless of whether the request ever reaches a render. Rows
    # being `_destroy`d are excluded from the preload (Rails skips
    # validations on records marked for destruction, so preloading their
    # attachment would itself be an UNUSED eager load — the destroy-only
    # spec below caught exactly that). Also loads @room.gallery_images into
    # memory, which media_change? below relies on to detect a genuine
    # position change per row.
    preload_gallery_image_attachments(skip_ids: destroyed_gallery_image_ids(attrs))

    curated_keys  = CURATED_PARAMS.map(&:to_s)
    curated_attrs = attrs.slice(*curated_keys)
    media_attrs   = attrs.except(*curated_keys)

    curated_result = apply_curated_change(curated_attrs)
    # Skip the media half entirely once the curated half has already failed
    # (nil counts as "didn't fail" — nothing to apply): a curated validation
    # error should re-render :edit immediately, not additionally attempt
    # (and possibly itself fail, confusingly, on top of) a media mutation the
    # user hasn't even seen an error for yet.
    media_result = apply_media_change(media_attrs) if curated_result.nil? || curated_result.success?

    failed_result = [ curated_result, media_result ].compact.find { |result| !result.success? }

    if failed_result
      # result.failure → @room carries the model's own validation errors
      # (result.payload[:record] is the same in-memory @room Curation::Apply
      # attempted to save!, so re-rendering :edit shows exactly what failed).
      @room = failed_result.payload[:record] || @room
      build_blank_gallery_images
      render :edit, status: :unprocessable_entity
    else
      redirect_to room_path(@room), notice: t("rooms.edit.success")
    end
  end

  # Phase 5 Task 5 (Brief §14.1): one-way editor hide. `authorize @room,
  # :hide?` covers both grantees RoomPolicy#hide? allows — an admin, or the
  # room's assigned-unit editor while it's still visible — Room#hide! is the
  # same audited call either way. The redirect branches on the ACTOR, not a
  # role check duplicated here: `policy(@room).show?` re-evaluates
  # RoomPolicy for the now-hidden record, which is false for an editor (an
  # editor loses sight of a room the instant they hide it — the "one-way"
  # half of the brief) and true for an admin (RoomPolicy#show? admits
  # `grant.admin?` unconditionally). Reusing `policy(@room).show?` here
  # rather than re-deriving "is this actor an admin" keeps the branch
  # anchored to the same predicate the next GET /rooms/:id would itself
  # re-check via redirect_inactive_for_non_admins.
  def hide
    authorize @room, :hide?
    @room.hide!(actor: Current.user)
    redirect_to policy(@room).show? ? room_path(@room) : find_a_room_path,
                notice: t("rooms.hide.success")
  end

  # Admin-only (RoomPolicy#unhide?) — always lands back on the room, since
  # only an admin ever reaches this action and an admin can always see it.
  def unhide
    authorize @room, :unhide?
    @room.unhide!(actor: Current.user)
    redirect_to room_path(@room), notice: t("rooms.unhide.success")
  end

  private

  # Blank "add a photo" rows for the gallery card, up to the D9 five-image
  # cap (app/models/room_gallery_image.rb) — `.build` appends to the
  # association's in-memory target, so the view's single `fields_for
  # :gallery_images` loop picks up both persisted rows and these unsaved ones
  # (branching per-row on `persisted?`) without a second query. `.size` and
  # `.map` below read that same target, counting any rows a failed #update
  # already re-built via nested attributes (so a re-render never double-adds
  # blanks past the cap). Preloading runs AFTER build (harmless either order —
  # it only touches already-persisted rows) so both #edit's first render and
  # a failed #update's re-render get it.
  def build_blank_gallery_images
    remaining = 5 - @room.gallery_images.size
    if remaining.positive?
      next_position = (@room.gallery_images.map(&:position).compact.max || -1) + 1
      remaining.times { |i| @room.gallery_images.build(position: next_position + i) }
    end

    preload_gallery_image_attachments
  end

  # Phase 5 Task 6: the curated half of #update's split. Assigns directly
  # (not through Curation::Apply) so `@room.changed?` can be checked BEFORE
  # deciding whether an ActivityLog is warranted — an admin/editor resubmits
  # the curated fields on every save (they're plain always-rendered form
  # fields), so "were these keys present" is not the same question as "did
  # anything actually change"; only the latter should write a log. Calling
  # Curation::Apply with no `attributes:` (its default `{}`) afterward is
  # deliberate: the assignment already happened on this same @room instance,
  # so Apply's own `@record.assign_attributes({}) if {}.present?` is a no-op
  # and its diff computation sees exactly the change made here.
  def apply_curated_change(curated_attrs)
    return nil if curated_attrs.blank?

    @room.assign_attributes(curated_attrs)
    return nil unless @room.changed?

    Curation::Apply.call(record: @room, actor: Current.user, action: "room.updated")
  end

  # Phase 5 Task 6: the media half. Unlike curated fields, attachment
  # operations are NOT dirty-tracked (has_one_attached assignment, and the
  # remove_* writers' purge_later call, never touch
  # ActiveRecord::AttributeMethods::Dirty), so "did anything change" can't be
  # answered by inspecting @room after assignment — media_change? below
  # inspects the SUBMITTED params instead, before Curation::Apply ever
  # assigns them (assigning is what triggers a remove_* writer's purge_later
  # side effect, so this check must run first either way).
  def apply_media_change(media_attrs)
    return nil unless media_change?(media_attrs)

    Curation::Apply.call(record: @room, actor: Current.user,
                         action: "room.media_updated", attributes: media_attrs)
  end

  # True when the submitted media_attrs represent a genuine attempted
  # change: a real file for one of the three attachment slots, a CHECKED
  # remove_* box (cast through ActiveModel::Type::Boolean, not `.present?` —
  # an unchecked checkbox still submits "0", which IS present as a string),
  # or a gallery row that isn't a no-op resubmission (see gallery_row_changed?).
  def media_change?(media_attrs)
    attrs = media_attrs.with_indifferent_access

    return true if %w[photo panorama seating_chart].any? { |key| attrs[key].present? }
    return true if %w[remove_photo remove_panorama remove_seating_chart]
                     .any? { |key| ActiveModel::Type::Boolean.new.cast(attrs[key]) }

    submitted_gallery_rows(attrs).any? { |row| gallery_row_changed?(row) }
  end

  # A gallery row counts as changed when it's marked `_destroy`, is a brand
  # new row with a real image chosen (the D9 blank "add another photo" rows
  # this controller always renders up to the five-image cap submit an EMPTY
  # image otherwise — reject_if's own `image.blank?` check on the model side
  # mirrors this), or is an existing row whose submitted position actually
  # differs from its current one (the position field is always resubmitted
  # by the form for every persisted row, even an untouched one, so presence
  # alone would false-positive on every request that merely renders the
  # gallery card). Relies on @room.gallery_images already being loaded
  # in-memory (preload_gallery_image_attachments, called before this in
  # #update) so this never issues its own query.
  def gallery_row_changed?(row)
    return true if ActiveModel::Type::Boolean.new.cast(row[:_destroy])
    return row[:image].present? if row[:id].blank?

    existing = @room.gallery_images.detect { |image| image.id.to_s == row[:id].to_s }
    existing.present? && row[:position].present? && existing.position.to_s != row[:position].to_s
  end

  # The view renders every persisted gallery image's `image.variant(...)`
  # (thumbnail) and RoomGalleryImage's own `validates :image, attached: true`
  # re-checks `image.attached?` per row on save — both N+1 without this.
  # `ActiveRecord::Associations::Preloader` (not `.includes`) is the one API
  # that can preload ONTO already-loaded, in-memory records: `@room` was
  # fetched via a plain `find` in `set_room`, and `build_blank_gallery_images`
  # may have already appended unsaved rows to `@room.gallery_images`' target —
  # re-querying via `.includes` would return a SEPARATE set of instances,
  # losing those unsaved rows. `select(&:persisted?)` skips new/blank rows
  # (they have no attachment to preload). Mirrors rooms/_media.html.erb's
  # `includes(image_attachment: :blob)` choice over the auto-generated
  # `with_attached_image` scope (that scope also preloads `variant_records`,
  # which Bullet flags as unused here).
  #
  # `skip_ids:` excludes rows the caller already knows are being `_destroy`d
  # this request — Rails skips validations on a record marked for
  # destruction, so preloading ITS attachment ahead of `#update`'s save would
  # itself be an unused eager load (Bullet caught exactly this on the
  # destroy-only spec). Not used before a render (#edit, or #update's failure
  # re-render still wants every row's thumbnail, destroy-marked or not).
  def preload_gallery_image_attachments(skip_ids: [])
    persisted = @room.gallery_images.select { |image| image.persisted? && skip_ids.exclude?(image.id.to_s) }
    return if persisted.empty?

    ActiveRecord::Associations::Preloader.new(
      records: persisted, associations: { image_attachment: :blob }
    ).call
  end

  # Ids of gallery images the submitted params mark for destruction this
  # request — see preload_gallery_image_attachments' `skip_ids:` above.
  def destroyed_gallery_image_ids(attrs)
    submitted_gallery_rows(attrs)
      .select { |row| ActiveModel::Type::Boolean.new.cast(row[:_destroy]) }
      .map { |row| row[:id].to_s }
      .compact
  end

  # True when `gallery_images_attributes` names an `:id` that is NOT one of
  # `@room`'s own gallery images — a foreign room's gallery image id, or one
  # destroyed between this page's load and this submit. Compared as strings
  # (`gallery_image_ids` are Integers, submitted ids are form strings) so
  # `"7" == 7` doesn't silently fail the `include?` check. Mirrors
  # BuildingsController#stale_floor_ids?.
  def stale_gallery_ids?(attrs)
    submitted_ids = submitted_gallery_rows(attrs).map { |row| row[:id].to_s }.compact_blank
    return false if submitted_ids.empty?

    known_ids = @room.gallery_image_ids.map(&:to_s)
    submitted_ids.any? { |id| known_ids.exclude?(id) }
  end

  # Shared row-extraction for destroyed_gallery_image_ids and
  # stale_gallery_ids? — `room_params.to_h`'s nested gallery_images_attributes
  # hash and its per-row hashes are both plain Hash by the time they reach
  # here, and Rails' own `fields_for` always submits this as a hash keyed by
  # index (never a bare array), but the defensive `Array(...)`/`.is_a?(Hash)`
  # branch (mirrors BuildingsController#submitted_floor_rows) tolerates
  # either shape. Each returned row is already `.with_indifferent_access`'d
  # so callers can read `row[:id]`/`row[:_destroy]` directly.
  def submitted_gallery_rows(attrs)
    rows = attrs.with_indifferent_access[:gallery_images_attributes]
    return [] if rows.blank?

    rows = rows.is_a?(Hash) ? rows.values : Array(rows)
    rows.map(&:with_indifferent_access)
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

  def filter_params
    params.permit(:building, :room, :unit_id, :capacity_min, :capacity_max,
                  :sort, :per, :view, characteristics: [])
  end

  # Phase 5 Task 6 (Brief §14.1): the authorization boundary itself (see
  # CURATED_PARAMS/MEDIA_PARAMS above) — CURATED_PARAMS is always permitted
  # (RoomPolicy#update? admits both an admin and the room's unit editor),
  # MEDIA_PARAMS only when `policy(@room).manage_media?` (admin-only). An
  # editor's submitted photo/panorama/seating_chart/remove_*/
  # gallery_images_attributes are dropped HERE, before Curation::Apply (or
  # anything else) ever sees them — not merely hidden from the edit view.
  # `params.expect` (Rails 8) over `params.require(...).permit(...)`: same
  # require-then-permit contract (raises ActionController::ParameterMissing
  # if `:room` is absent, silently drops any unlisted key), but its
  # shape-checked nested syntax is what MEDIA_PARAMS' double-array
  # gallery_images_attributes entry above is written for.
  def room_params
    permitted = CURATED_PARAMS.dup
    permitted.concat(MEDIA_PARAMS) if policy(@room).manage_media?
    params.expect(room: permitted)
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
