class OnboardingsController < ApplicationController
  skip_onboarding_requirement

  def show
    return redirect_to(root_path) if Current.user.onboarded?

    redirect_to new_onboarding_workspace_path
  end

  def update
    Current.user.update!(onboarded_at: Time.current) unless Current.user.onboarded?

    workspace = Current.user.onboarding_workspace
    if workspace
      redirect_to workspace_path(workspace), notice: t(".complete")
    else
      redirect_to root_path, notice: t(".complete")
    end
  end
end
