class WorkspacesController < ApplicationController
  include WorkspaceScoped
  skip_before_action :set_workspace, only: [ :index, :new, :create ]

  def index
    authorize Workspace
    @workspaces = Current.user.workspaces.kept.includes(:logo_attachment)
  end

  def new
    authorize Workspace
    @workspace = Workspace.new
  end

  def create
    authorize Workspace
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
    authorize @workspace
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

  def workspace_params
    params.require(:workspace).permit(:name)
  end
end
