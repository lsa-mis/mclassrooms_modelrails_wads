# Posture gate: under TENANCY_WORKSPACE_CREATION=disabled (typically the
# :shared preset), additional workspace creation is forbidden. UI omits the
# links, but a direct URL still needs to be refused. See app/docs/developer/presets.md.
module RequiresWorkspaceCreationEnabled
  extend ActiveSupport::Concern

  included do
    before_action :ensure_workspace_creation_enabled, only: %i[new create]
  end

  private

  def ensure_workspace_creation_enabled
    return if TenancyConfig.workspace_creation_enabled?
    redirect_to root_path, alert: t("workspaces.creation_disabled")
  end
end
