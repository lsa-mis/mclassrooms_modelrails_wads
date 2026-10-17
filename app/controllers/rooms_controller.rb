class RoomsController < ApplicationController
  include DirectoryScoped
  include PublicDirectoryChrome
  include RoomEditPage

  VIEWS = %w[active inactive_rooms inactive_buildings].freeze

  CURATED_PARAMS = [ :nickname, :ada_seat_count ].freeze

  before_action :set_room, only: [ :show, :edit, :update ]
  # Show only: an admin must still reach a hidden room to edit or unhide it.
  before_action :redirect_inactive_for_non_admins, only: [ :show ]

  def index
    authorize Room
    @filter_params = filter_params
    @search = RoomSearch.new(@filter_params, base: base_scope, saved_for: Current.user)
    @pagy, @rooms = pagy(:offset, @search.results, limit: @search.per_page)
    @filter_groups = CharacteristicFilterGroups.filters
    @note_stats = Note.roots.where(notable_type: "Room", notable_id: @rooms.map(&:id))
                      .group(:notable_id, :alert).count
    @saved_room_ids = Current.user.saved_rooms.where(room_id: @rooms.map(&:id)).pluck(:room_id, :id).to_h
    @saved_count = Current.user.saved_rooms.where(workspace: Current.workspace).count
    @announcement = Announcement.for(:find_a_room_page)
    respond_to do |format|
      format.html # never fresh_when here — D14: results are live queries
      format.json
    end
  end

  def show
    authorize @room
    @presenter = RoomPresenter.new(@room, url: room_url(@room))
    @saved_id = Current.user.saved_rooms.find_by(room_id: @room.id)&.id

    # D14 keeps Rails' default Cache-Control; no-store is deliberately unset. See /docs/developer/rooms-directory.
    if stale?(etag: show_cache_key, last_modified: show_last_modified)
      respond_to do |format|
        format.html
        format.json do
          # Preloads only here: a 304 must not carry an unused eager load.
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

  # Authorize view_inactive? first; policy_scope can never reach resolve_including_inactive.
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

  # building and room stay permitted for links shared before the redesign.
  def filter_params
    params.permit(:q, :building, :room, :unit_id, :capacity_min, :capacity_max,
                  :sort, :per, :view, :saved, characteristics: [])
  end

  def room_params
    params.expect(room: CURATED_PARAMS)
  end

  # Attachments count by created_at: the table has no updated_at. See /docs/developer/rooms-directory.
  def show_cache_key
    [ @room, @room.room_contact, RoleResolver.for(Current.user).admin?, @saved_id,
      @room.notes.maximum(:updated_at), @room.building.notes.maximum(:updated_at),
      media_attachments.maximum(:created_at) ]
  end

  def show_last_modified
    [ @room.updated_at, @room.notes.maximum(:updated_at),
      @room.building.notes.maximum(:updated_at),
      media_attachments.maximum(:created_at) ].compact.max
  end

  # MediaAsset.name, not a literal: a rename must break this, not silently match nothing.
  def media_attachments
    ActiveStorage::Attachment.where(record_type: "Room", record_id: @room.id)
      .or(ActiveStorage::Attachment.where(record_type: MediaAsset.name, record_id: @room.gallery_ids))
  end

  def set_room
    # Not .listed: an admin must reach a hidden room, and the inactive redirect needs it.
    @room = Room.for_current_workspace.find_by!(rmrecnbr: params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to find_a_room_path, alert: t("rooms.show.not_found")
  end

  def redirect_inactive_for_non_admins
    return unless @room.hidden?
    return if RoleResolver.for(Current.user).admin?
    redirect_to find_a_room_path, notice: t("rooms.inactive_notice")
  end
end
