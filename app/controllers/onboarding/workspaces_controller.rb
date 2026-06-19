module Onboarding
  class WorkspacesController < BaseController
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
        redirect_to new_onboarding_project_path, notice: t(".success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def workspace_params
      params.require(:workspace).permit(:name)
    end
  end
end
