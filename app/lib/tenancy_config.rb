# Posture-aware reader for the tenancy preset configuration. Centralizes
# the few call sites that need to ask "which preset are we?" so the rest
# of the app stays posture-agnostic. See app/docs/presets.md.
module TenancyConfig
  module_function

  def onboarding
    Rails.configuration.x.tenancy.onboarding
  end

  def personal?
    onboarding == :personal
  end

  def shared?
    onboarding == :shared
  end

  def none?
    onboarding == :none
  end

  def workspace_creation_enabled?
    Rails.configuration.x.tenancy.workspace_creation == :enabled
  end

  def shared_workspace_slug
    Rails.configuration.x.tenancy.shared_workspace_slug
  end

  def shared_workspace
    return nil unless shared?
    Workspace.find_by(slug: shared_workspace_slug)
  end
end
