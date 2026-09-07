module Workspaces
  # Authorizes workspace identity edits (name, logo, primary_color) on
  # the consolidated workspaces#edit page (Profile). Gated on
  # manage_settings — mirrors the previous BrandingPolicy capability
  # surface so Admins who could edit branding before route
  # consolidation continue to edit Profile after. Tightening to
  # manage_workspace (Owner-only) would silently cut a capability
  # Admins currently rely on; see #144 wontfix rationale.
  class ProfilePolicy < ApplicationPolicy
    def edit?
      can?("manage_settings")
    end

    def update?
      can?("manage_settings")
    end
  end
end
