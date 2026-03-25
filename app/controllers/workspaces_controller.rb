class WorkspacesController < ApplicationController
  before_action :set_workspace, only: [:show, :edit, :update, :destroy]

  def index
    @workspaces = Current.user.workspaces.kept
  end

  def new
    @workspace = Workspace.new
  end

  def create
    @workspace = Workspace.new(workspace_params)
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

  def edit
  end

  def update
    authorize @workspace
    if @workspace.update(workspace_params)
      redirect_to workspace_path(@workspace), notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @workspace
    @workspace.discard!
    redirect_to workspaces_path, notice: t(".success")
  end

  private

  def set_workspace
    @workspace = Current.user.workspaces.kept.find_by!(slug: params[:slug])
    Current.workspace = @workspace
    session[:current_workspace_id] = @workspace.id
  rescue ActiveRecord::RecordNotFound
    redirect_to workspaces_path, alert: t("workspaces.not_found")
  end

  def workspace_params
    params.require(:workspace).permit(:name)
  end
end
