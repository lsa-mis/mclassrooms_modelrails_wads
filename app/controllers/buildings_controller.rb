class BuildingsController < ApplicationController
  include DirectoryScoped
  include PublicDirectoryChrome

  before_action :set_building, only: [ :show, :edit, :update ]

  def index
    authorize Building
    scope_policy = BuildingPolicy::Scope.new(pundit_user, Building)
    scope = if params[:show_hidden] == "1" && policy(Building).view_inactive?
      scope_policy.resolve_including_hidden
    else
      scope_policy.resolve
    end
    # .where, not .merge: merge would drop with_classrooms' id predicate and leak classroom-less buildings.
    scope = scope.where(id: Building.search_name(params[:q])) if params[:q].present?

    @pagy, @buildings = pagy(scope.order(:name).includes(:campus))

    # One grouped count per page: Bullet cannot catch a per-row .count on a loaded record.
    @classroom_counts = Room.classroom.where(building_id: @buildings.map(&:id)).group(:building_id).count

    respond_to do |format|
      format.html
      format.json { render json: index_json }
    end
  end

  def show
    authorize @building

    @floors = @building.floors.order(:label).includes(plan_attachment: :blob)
    floor_ids = @floors.map(&:id) # forces the load now, so `@floors.any?` in the view reuses it for free

    @floor_classroom_counts = Room.classroom.where(floor_id: floor_ids).group(:floor_id).count

    # order(:floor_id, :id) keeps each floor's first classroom its lowest id.
    @floor_representative_rooms = Room.classroom.where(floor_id: floor_ids).order(:floor_id, :id).group_by(&:floor_id)

    respond_to do |format|
      format.html
      format.json { render json: show_json }
    end
  end

  def edit
    authorize @building
    load_floors
  end

  def update
    authorize @building
    attrs = building_params.to_h

    # Before assign_attributes: a foreign or deleted floor id raises outside Curation::Apply. See /docs/developer/rooms-directory (Who may save what).
    if stale_floor_ids?(attrs)
      load_floors
      flash.now[:alert] = t("buildings.edit.stale_floor")
      render :edit, status: :unprocessable_entity
      return
    end

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

  private

  def load_floors
    @floors = @building.floors.order(:label).includes(plan_attachment: :blob)
  end

  # Only floors getting a new plan, and plan_blob too: Bullet flags missing and unused preloads. See /docs/developer/rooms-directory (Who may save what).
  def preload_new_floor_plan_attachments(attrs)
    ids = floor_ids_with_new_plan(attrs)
    return if ids.empty?

    floors = @building.floors.select { |floor| ids.include?(floor.id.to_s) }
    return if floors.empty?

    ActiveRecord::Associations::Preloader.new(
      records: floors, associations: [ :plan_blob, { plan_attachment: :blob } ]
    ).call
  end

  def floor_ids_with_new_plan(attrs)
    submitted_floor_rows(attrs).select { |row| row[:plan].present? }
                                .map { |row| row[:id].to_s }
                                .compact
  end

  def stale_floor_ids?(attrs)
    submitted_ids = submitted_floor_rows(attrs).map { |row| row[:id].to_s }.compact_blank
    return false if submitted_ids.empty?

    known_ids = @building.floor_ids.map(&:to_s)
    submitted_ids.any? { |id| known_ids.exclude?(id) }
  end

  def submitted_floor_rows(attrs)
    rows = attrs.with_indifferent_access[:floors_attributes]
    return [] if rows.blank?

    rows = rows.is_a?(Hash) ? rows.values : Array(rows)
    rows.map(&:with_indifferent_access)
  end

  def set_building
    # Not .listed: an admin must reach a hidden building.
    @building = Building.for_current_workspace.find_by!(bldrecnbr: params[:id])
  end

  # No address or visibility fields: the sync owns the address, and hiding is its own resource. See /docs/developer/rooms-directory (Who may save what).
  def building_params
    params.require(:building).permit(
      :nickname, :short_name, :photo, :remove_photo,
      :photo_alt, :photo_description,
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
      photo_url: variant_url(@building.photo, :hero),
      floors: @floors.map { |floor| floor_json(floor) }
    }
  end

  def floor_json(floor)
    {
      id: floor.id,
      label: floor.label,
      plan_url: plan_url(floor.plan),
      classroom_count: @floor_classroom_counts.fetch(floor.id, 0)
    }
  end

  # A webp representation for images, never the original: these slots accept HEIC.
  def variant_url(attachment, name)
    return nil unless attachment.attached?

    rails_representation_url(attachment.variant(name))
  end

  # A PDF keeps its blob URL: .variant raises on a PDF.
  def plan_url(attachment)
    return nil unless attachment.attached?
    return rails_blob_url(attachment) if attachment.content_type == "application/pdf"

    variant_url(attachment, :display)
  end
end
