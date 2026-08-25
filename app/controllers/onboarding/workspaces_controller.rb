module Onboarding
  class WorkspacesController < BaseController
    def new
      authorize Workspace
      @workspace = Workspace.new
    end

    def create
      authorize Workspace
      @workspace = Workspace.create_owned(workspace_params, owner: Current.user)

      # create_owned makes the workspace + owner membership atomic (#676).
      # Fork: onboarding is single-step (no project/tools/team steps), so
      # completion happens here and lands in the new workspace.
      if @workspace.persisted?
        Current.user.update!(onboarded_at: Time.current)
        redirect_to workspace_path(@workspace), notice: t(".success")
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
