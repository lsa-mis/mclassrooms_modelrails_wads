module Onboarding
  class BaseController < ApplicationController
    skip_onboarding_requirement
    layout "onboarding"

    before_action :require_not_onboarded
    before_action :set_onboarding_workspace

    # A refusal inside the wizard means the user's data already put them past
    # its purpose (the steps assume a founder; a Member cannot invite). Leave
    # for good: ApplicationController's workspace redirect would land on a
    # page the onboarding guard bounces straight back here.
    rescue_from Pundit::NotAuthorizedError, with: :leave_onboarding

    private

    def require_not_onboarded
      redirect_to root_path if Current.user.onboarded?
    end

    def leave_onboarding
      Current.user.update!(onboarded_at: Time.current) unless Current.user.onboarded?
      redirect_to(@workspace ? workspace_path(@workspace) : root_path)
    end

    # During first-run the user owns exactly one workspace; resolve it so the
    # project/team steps run inside its tenancy scope. Nil at the workspace step.
    def set_onboarding_workspace
      @workspace = Current.user.onboarding_workspace
      Current.workspace = @workspace if @workspace
    end
  end
end
