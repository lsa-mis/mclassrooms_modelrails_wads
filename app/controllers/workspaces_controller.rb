class WorkspacesController < ApplicationController
  include WorkspaceScoped
  skip_before_action :set_workspace, only: [ :index, :new, :create ]
  before_action :ensure_workspace_creation_enabled, only: [ :new, :create ]

  # Mirrors settings/avatars_controller: #update purges attachments and writes
  # blobs, so it gets the same per-user budget (2026-08-12 reauth panel fold-in).
  rate_limit to: 20, within: 3.minutes, only: :update,
    by: -> { Current.user&.id || request.remote_ip },
    with: -> {
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: error_toast(t("workspaces.update.rate_limited")),
                 status: :too_many_requests
        end
        format.html { redirect_to workspaces_path, alert: t("workspaces.update.rate_limited") }
      end
    }

  def index
    authorize Workspace

    # No `:user` on the outer scope — the row partial uses `Current.user`
    # directly (membership.user is always Current.user on this page). Inner
    # `memberships: { user: ... }` stays because Workspace#owners walks the
    # *other* members' user records.
    scope = Current.user.memberships.kept
              .joins(:workspace)
              .merge(Workspace.kept.not_archived)
              .includes(
                :role,
                workspace: [ :logo_attachment, memberships: [ :role, :user ] ]
              )
              .order(Arel.sql("memberships.last_accessed_at DESC NULLS LAST, workspaces.name ASC"))

    @archived_memberships = Current.user.memberships.kept
              .joins(:workspace)
              .merge(Workspace.kept.archived)
              .includes(workspace: :logo_attachment)
              .order("workspaces.name ASC")
              .to_a

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

    result = @workspace.identity.apply(**identity_update_params)
    # Crop save (file present) keeps the modal open; hub save closes it.
    @close_modal = identity_update_params[:image].blank?

    if result.success?
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_workspace_path(@workspace), notice: t(".success") }
      end
    elsif result.error == :source_unavailable
      message = t("workspaces.brandings.source_unavailable")
      respond_to do |format|
        format.turbo_stream { render turbo_stream: error_toast(message), status: :forbidden }
        format.html { redirect_to edit_workspace_path(@workspace), alert: message }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: error_toast(result.error_message), status: :unprocessable_content }
        format.html { render :edit, status: :unprocessable_content }
      end
    end
  end

  # Lazy-loaded identity picker hub partial for the Profile page.
  def identity_picker_hub
    authorize @workspace, policy_class: Workspaces::ProfilePolicy
    identity = @workspace.identity

    render partial: "shared/identity_picker_hub",
      locals: {
        identity: identity,
        form_url: workspace_path(@workspace),
        hub_url: identity_picker_hub_workspace_path(@workspace),
        current_source: identity.resolve_source(params[:source])
      },
      layout: false
  end

  def destroy
    authorize @workspace
    @workspace.discard!
    redirect_to workspaces_path, notice: t(".success")
  end

  def archive
    authorize @workspace
    @workspace.archive!
    redirect_to workspaces_path, notice: t(".success")
  end

  def unarchive
    authorize @workspace
    @workspace.unarchive!
    redirect_to workspace_path(@workspace), notice: t(".success")
  end

  private

  # Posture gate: under TENANCY_WORKSPACE_CREATION=disabled (typically the
  # :shared preset), additional workspace creation is forbidden. UI omits the
  # links, but a direct URL still needs to be refused. See app/docs/developer/presets.md.
  def ensure_workspace_creation_enabled
    return if TenancyConfig.workspace_creation_enabled?
    redirect_to root_path, alert: t("workspaces.creation_disabled")
  end

  def create_params
    params.require(:workspace).permit(:name)
  end

  # The identity-picker JS posts avatar-named params for BOTH models (frozen
  # wire protocol); logo-named params serve non-JS callers. name arrives under
  # workspace[name] from the profile/customize forms — key-presence (not
  # blankness) decides whether it participates, so a blank rename still fails
  # validation inside apply's single save.
  def identity_update_params
    @identity_update_params ||= {
      image: params[:avatar] || params[:logo],
      image_original: params[:avatar_original] || params[:logo_original],
      crop_coordinates: params[:crop_coordinates],
      source: params[:avatar_source],
      color: params[:primary_color],
      name: workspace_attrs.key?(:name) ? workspace_attrs[:name] : nil
    }
  end

  # Strong-params extraction for the workspace-only `name` field: a non-scalar
  # value (e.g. workspace[name][foo]=bar) is dropped by permit, so it never
  # reaches Identity#apply as anything but absent (nil).
  def workspace_attrs
    params.fetch(:workspace, {}).permit(:name)
  end
end
