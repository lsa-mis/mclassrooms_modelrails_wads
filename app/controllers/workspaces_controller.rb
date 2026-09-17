class WorkspacesController < ApplicationController
  include WorkspaceScoped
  include IdentityParams
  include RequiresWorkspaceCreationEnabled
  skip_before_action :set_workspace, only: [ :index, :new, :create ]

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

    # :workspace only — the archived section renders locked_row, which draws
    # no logo. The logo_attachment include that used to sit here was never
    # consumed by this page; Bullet keys "used" by class+id, and the header's
    # hamburger switcher happened to draw the same rows' logos until #1077
    # moved that switcher into workspace chrome. With that gone Bullet raises
    # on the dead include, which is the right complaint.
    @archived_memberships = Current.user.memberships.kept
              .joins(:workspace)
              .merge(Workspace.kept.archived)
              .includes(:workspace)
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
    @workspace = Workspace.create_owned(create_params, owner: Current.user)
    if @workspace.persisted?
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

  def destroy
    authorize @workspace
    @workspace.discard!
    redirect_to workspaces_path, notice: t(".success")
  end

  private

  def create_params
    params.require(:workspace).permit(:name)
  end

  # Workspace extras on top of IdentityParams#identity_wire_params: logo-named
  # params serve non-JS callers, and name arrives under workspace[name] from
  # the profile/customize forms — key-presence (not blankness) decides whether
  # it participates, so a blank rename still fails validation inside apply's
  # single save.
  def identity_update_params
    @identity_update_params ||= identity_wire_params.merge(
      image: params[:avatar] || params[:logo],
      image_original: params[:avatar_original] || params[:logo_original],
      name: workspace_attrs.key?(:name) ? workspace_attrs[:name] : nil
    )
  end

  # Strong-params extraction for the workspace-only `name` field: a non-scalar
  # value (e.g. workspace[name][foo]=bar) is dropped by permit, so it never
  # reaches Identity#apply as anything but absent (nil).
  def workspace_attrs
    params.fetch(:workspace, {}).permit(:name)
  end
end
