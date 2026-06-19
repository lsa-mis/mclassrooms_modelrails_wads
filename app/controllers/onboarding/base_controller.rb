module Onboarding
  class BaseController < ApplicationController
    skip_onboarding_requirement
    layout "onboarding"

    before_action :require_not_onboarded
    before_action :set_onboarding_workspace

    private

    def require_not_onboarded
      redirect_to root_path if Current.user.onboarded?
    end

    # During first-run the user owns exactly one workspace; resolve it so the
    # project/team steps run inside its tenancy scope. Nil at the account step.
    def set_onboarding_workspace
      @workspace = Current.user.workspaces.kept.first
      Current.workspace = @workspace if @workspace
    end
  end
end
