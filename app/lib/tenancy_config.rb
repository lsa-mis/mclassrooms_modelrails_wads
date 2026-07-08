# Posture-aware reader for the tenancy preset configuration. Centralizes
# the few call sites that need to ask "which preset are we?" so the rest
# of the app stays posture-agnostic. See app/docs/developer/presets.md.
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

  # Fork deviation (MiClassrooms Task 4): role slug a user is granted by
  # User#join_shared_workspace when self-joining the shared workspace.
  # Defaults to "member" (the template's original hardcoded value) so
  # behavior is unchanged unless a fork opts in via TENANCY_SHARED_JOIN_ROLE.
  # MiClassrooms sets this to "viewer" — see config/application.rb.
  def shared_join_role
    Rails.configuration.x.tenancy.shared_join_role
  end

  # Fork deviation (MiClassrooms final-review fix, M3): scoped to .kept —
  # mirrors the idiom DirectoryScoped uses elsewhere — so a discarded shared
  # workspace is treated as absent rather than resolved. Without this, a
  # directly-discarded shared workspace (the guarded Workspace#discard! API
  # can't discard a home workspace, but a console/rake/disaster-recovery path
  # writing discarded_at directly still can) would keep resolving here:
  # RoleResolver.for would still grant whatever role the user's existing
  # membership carries in that now-discarded workspace, and
  # User#join_shared_workspace would keep admitting new members into it.
  # Callers already have their own fail-safes around a nil return
  # (User#join_shared_workspace raises "not found"; RoleResolver.for grants
  # nothing) — this makes "discarded" resolve through the same nil path as
  # "doesn't exist", instead of silently leaking access through a
  # supposedly-gone workspace.
  def shared_workspace
    return nil unless shared?
    Workspace.kept.find_by(slug: shared_workspace_slug)
  end
end
