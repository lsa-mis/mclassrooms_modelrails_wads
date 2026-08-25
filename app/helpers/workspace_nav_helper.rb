module WorkspaceNavHelper
  # Which workspace section the current request belongs to. Today only
  # :settings is consumed (primary-nav active state + whether the secondary
  # sub-nav renders); Overview/Projects return nil. Derived from the
  # controller/action — a pure read, no per-controller macro. `:all` means
  # every action of that controller is a settings page; the array on
  # "workspaces" matches the old `layout "settings", only:` split, since
  # workspaces#show is the Overview, not a settings page.
  WORKSPACE_SETTINGS_ENDPOINTS = {
    "workspaces" => %w[edit update identity_picker_hub],
    "workspaces/settings" => :all,
    "workspaces/members" => :all,
    "workspaces/invitations" => :all
  }.freeze

  def current_workspace_section
    actions = WORKSPACE_SETTINGS_ENDPOINTS[controller.controller_path]
    return :settings if actions == :all || actions&.include?(controller.action_name)

    nil
  end

  # Workspace-shell nav items (Overview, Projects, and Settings for org
  # workspaces). Settings is active whenever the current page is a
  # workspace-settings-section page (see #current_workspace_section), so the
  # primary nav highlights correctly on every sub-page — Profile, Members,
  # Invitations, Limits & Plan — not just the Profile landing.
  def workspace_shell_nav_items
    workspace = Current.workspace
    items = [
      { label: t("workspaces.sidebar.overview"), href: workspace_path(workspace),
        icon: :home, active: current_page?(workspace_path(workspace)) },
      { label: t("workspaces.sidebar.projects"), href: workspace_projects_path(workspace),
        icon: :folder, active: current_page?(workspace_projects_path(workspace)) }
    ]
    unless workspace.personal?
      items << { label: t("workspaces.sidebar.settings"), href: edit_workspace_path(workspace),
                 icon: :cog, active: current_workspace_section == :settings }
    end
    items
  end
end
