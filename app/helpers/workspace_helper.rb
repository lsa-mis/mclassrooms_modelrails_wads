module WorkspaceHelper
  # Workspaces shown in the header context switcher, preloaded for the chip
  # (logo + role), N+1-safe. Memoized so the banner and switcher share one load.
  # Recency ordering is applied at render time via #workspaces_by_recency (not
  # here) so a solo user's single workspace isn't force-loaded just to be sorted.
  def switcher_workspaces
    @switcher_workspaces ||= Current.user.workspaces.kept.includes(:logo_attachment, memberships: :role)
  end

  # Recency order for a loaded switcher collection (most-recent access first,
  # then alphabetical) so the capped mobile switch list shows the workspaces a
  # user would actually reach for, not an arbitrary DB order. Call INSIDE the
  # "2+ workspaces" render branch only — sorting materializes the relation, and
  # outside a render Bullet flags the icon includes as an unused eager-load.
  def workspaces_by_recency(workspaces)
    workspaces.sort_by do |workspace|
      accessed = workspace.memberships.detect { |m| m.user_id == Current.user.id }&.last_accessed_at
      [ accessed ? 0 : 1, accessed ? -accessed.to_i : 0, workspace.name.downcase ]
    end
  end

  # The workspace the switcher trigger reflects: the active one on a workspace
  # page, else the last-visited one remembered in the session (e.g. on /me).
  def switcher_current_workspace
    Current.workspace || Current.user.workspaces.kept.find_by(id: session[:current_workspace_id])
  end

  WORKSPACE_ICON_SIZES = {
    sm: { css: "w-8 h-8", px: 32, text: "text-xs" },
    md: { css: "w-10 h-10", px: 40, text: "text-sm" },
    lg: { css: "w-16 h-16", px: 64, text: "text-xl" }
  }.freeze

  # Which workspace section the current request belongs to. Today only
  # :settings is consumed (primary-nav active state + whether the secondary
  # sub-nav renders); Overview returns nil. Derived from the
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

  # Workspace-shell nav items (Overview, and Settings for org workspaces).
  # Settings is active whenever the current page is a workspace-settings-section
  # page (see #current_workspace_section), so the primary nav highlights
  # correctly on every sub-page — Profile, Members, Invitations, Limits & Plan
  # — not just the Profile landing.
  def workspace_shell_nav_items
    workspace = Current.workspace
    items = [
      { label: t("workspaces.sidebar.overview"), href: workspace_path(workspace),
        icon: :home, active: current_page?(workspace_path(workspace)) }
    ]
    unless workspace.personal?
      items << { label: t("workspaces.sidebar.settings"), href: edit_workspace_path(workspace),
                 icon: :cog, active: current_workspace_section == :settings }
    end
    items
  end

  def workspace_icon_for(workspace, size: :md)
    config = WORKSPACE_ICON_SIZES.fetch(size)

    if workspace.logo.attached?
      render_workspace_logo(workspace, config)
    elsif workspace.personal? && workspace.owner&.avatar&.attached? && workspace.owner.avatar_source == "upload"
      render_owner_avatar_fallback(workspace, config)
    else
      render_workspace_initials(workspace, config)
    end
  end

  private

  def render_workspace_logo(workspace, config)
    variant = workspace.logo.variant(resize_to_fill: [ config[:px], config[:px] ])
    # main_app.url_for is required because the shared header / workspace
    # switcher render inside the markdowndocs engine layout too — and
    # `image_tag variant` from a non-main-app context fails (Active Storage
    # routes live on main_app, not engine routers). See avatar_helper for
    # the same fix; same pattern, same reason.
    image_tag main_app.url_for(variant),
      class: "#{config[:css]} rounded-full object-cover",
      alt: workspace.name,
      aria: { hidden: true }
  end

  def render_owner_avatar_fallback(workspace, config)
    avatar_for(workspace.owner, size: WORKSPACE_ICON_SIZES.key(config))
  end

  def render_workspace_initials(workspace, config)
    hue = workspace.primary_color || 210

    content_tag :div, workspace.initials,
      class: "#{config[:css]} #{config[:text]} rounded-full flex items-center justify-center
              font-semibold text-white bg-hue-initials",
      style: "--hue: #{hue}",
      aria: { hidden: true }
  end
end
