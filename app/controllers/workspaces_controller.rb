class WorkspacesController < ApplicationController
  include WorkspaceScoped
  include CropCoordinatable
  skip_before_action :set_workspace, only: [ :index, :new, :create ]
  before_action :ensure_workspace_creation_enabled, only: [ :new, :create ]

  layout "settings", only: [ :edit, :update, :identity_picker_hub ]
  settings_context :workspace

  def index
    authorize Workspace

    # No `:user` on the outer scope — the row partial uses `Current.user`
    # directly (membership.user is always Current.user on this page). Inner
    # `memberships: { user: ... }` stays because Workspace#owners walks the
    # *other* members' user records.
    scope = Current.user.memberships.kept
              .joins(:workspace)
              .merge(Workspace.kept)
              .includes(
                :role,
                workspace: [ :logo_attachment, memberships: [ :role, :user ] ]
              )
              .order(Arel.sql("memberships.last_accessed_at DESC NULLS LAST, workspaces.name ASC"))

    @memberships = scope.to_a
    @current_membership = @memberships.first
    @other_memberships = @memberships.drop(1)
  end

  def new
    authorize Workspace
    @workspace = Workspace.new
  end

  def create
    authorize Workspace
    @workspace = Workspace.new(create_params)
    if @workspace.save
      owner_role = Role.find_by!(slug: "owner", workspace_id: nil)
      @workspace.memberships.create!(user: Current.user, role: owner_role)
      redirect_to workspace_path(@workspace), notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    authorize @workspace
  end

  # Workspace Profile (identity: name, logo, primary_color, logo_source).
  # Operational config (capacity/plan) lives on Workspaces::SettingsController#edit.
  def edit
    authorize @workspace, policy_class: Workspaces::ProfilePolicy
  end

  def update
    authorize @workspace, policy_class: Workspaces::ProfilePolicy

    # JS saveCrop sends "avatar"/"avatar_original" to match User flow —
    # accept those as aliases for logo/logo_original.
    cropped_image = params[:avatar] || params[:logo]
    original_image = params[:avatar_original] || params[:logo_original]

    if params[:avatar_source].present? && !@workspace.available_logo_sources.include?(params[:avatar_source])
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("toast-cards",
            partial: "shared/toast_card",
            locals: { type: :error, message: t("workspaces.brandings.source_unavailable") }),
                 status: :forbidden
        end
        format.html { redirect_to edit_workspace_path(@workspace), alert: t("workspaces.brandings.source_unavailable") }
      end
      return
    end

    if cropped_image.present?
      @workspace.logo.attach(cropped_image)
      @workspace.logo_source = "upload"
    end

    if original_image.present?
      @workspace.logo_original.attach(original_image)
    end

    if params[:crop_coordinates].present? && @workspace.logo_original.attached?
      coords = safe_parse_coordinates(params[:crop_coordinates])
      if coords
        blob = @workspace.logo_original.blob
        blob.update!(metadata: blob.metadata.merge("crop" => coords))
      end
    end

    if params[:avatar_source].present? && cropped_image.blank?
      source = params[:avatar_source]
      @workspace.logo_source = source
      if source != "upload"
        @workspace.logo.purge if @workspace.logo.attached?
        @workspace.logo_original.purge if @workspace.logo_original.attached?
      end
    end

    if params[:primary_color].present?
      @workspace.primary_color = params[:primary_color].to_i
    end

    # Crop save (logo file present) keeps modal open; hub save (no logo) closes it.
    @close_modal = cropped_image.blank?

    if @workspace.update(profile_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_workspace_path(@workspace), notice: t(".success") }
      end
    else
      @workspace.logo.purge if cropped_image.present?
      @workspace.logo_original.purge if original_image.present?

      error_message = @workspace.errors.full_messages.to_sentence

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("toast-cards",
            partial: "shared/toast_card",
            locals: { type: :error, message: error_message }),
                 status: :unprocessable_content
        end
        format.html { render :edit, status: :unprocessable_content }
      end
    end
  end

  # Lazy-loaded identity picker hub partial for the Profile page.
  def identity_picker_hub
    authorize @workspace, policy_class: Workspaces::ProfilePolicy

    @source = if params[:source].present? && @workspace.available_logo_sources.include?(params[:source])
                params[:source]
    else
                @workspace.logo_source
    end

    is_user = false
    has_image = @workspace.logo.attached?
    current_hue = @workspace.primary_color || 210
    display_url = has_image ? url_for(@workspace.logo) : nil

    render partial: "shared/identity_picker_hub",
      locals: {
        model: @workspace,
        form_url: workspace_path(@workspace),
        hub_url: identity_picker_hub_workspace_path(@workspace),
        current_source: @source,
        has_color_picker: true,
        available_sources: @workspace.available_logo_sources,
        is_user: is_user,
        has_image: has_image,
        current_hue: current_hue,
        display_url: display_url,
        gravatar_url: nil,
        initials: @workspace.initials,
        hub_title: t("identity_picker.choose_workspace_logo")
      },
      layout: false
  end

  def destroy
    authorize @workspace
    @workspace.discard!
    redirect_to workspaces_path, notice: t(".success")
  end

  private

  # Posture gate: under TENANCY_WORKSPACE_CREATION=disabled (typically the
  # :shared preset), additional workspace creation is forbidden. UI omits the
  # links, but a direct URL still needs to be refused. See app/docs/presets.md.
  def ensure_workspace_creation_enabled
    return if TenancyConfig.workspace_creation_enabled?
    redirect_to root_path, alert: t("workspaces.creation_disabled")
  end

  def create_params
    params.require(:workspace).permit(:name)
  end

  def profile_params
    params.fetch(:workspace, {}).permit(:name, :primary_color)
  end
end
