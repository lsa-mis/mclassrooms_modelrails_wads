class OnboardingsController < ApplicationController
  skip_onboarding_requirement

  # Single entry point: compute the derived step and redirect to it.
  def show
    return redirect_to(root_path) if Current.user.onboarded?

    workspace = Current.user.workspaces.kept.first
    if workspace.nil?
      redirect_to new_onboarding_workspace_path
    elsif workspace.projects.kept.none?
      redirect_to new_onboarding_project_path
    else
      redirect_to new_onboarding_team_path
    end
  end

  # "Skip for now" / finish: mark complete and land in the workspace.
  def update
    Current.user.update!(onboarded_at: Time.current) unless Current.user.onboarded?

    workspace = Current.user.workspaces.kept.first
    if workspace && (project = workspace.projects.kept.first)
      redirect_to workspace_project_path(workspace, project), notice: t(".complete")
    elsif workspace
      redirect_to workspace_path(workspace), notice: t(".complete")
    else
      redirect_to root_path, notice: t(".complete")
    end
  end
end
