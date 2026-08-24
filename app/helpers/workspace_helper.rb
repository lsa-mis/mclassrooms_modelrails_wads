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
  # page, else the last-visited one remembered in the session (e.g. on /me),
  # else the most-recently-accessed membership. The last fallback covers the
  # first requests after login — start_new_session_for resets the session, so
  # session[:current_workspace_id] is empty until a workspace page is visited,
  # and without it the header rendered a blank switcher chip.
  def switcher_current_workspace
    Current.workspace ||
      Current.user.workspaces.kept.find_by(id: session[:current_workspace_id]) ||
      last_accessed_workspace
  end

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
    identity = workspace.identity

    # The personal-workspace → owner-avatar fallback is deliberately helper-level
    # composition of two identities, not something WorkspaceIdentity models —
    # see the CTRL-1 design's non-goals.
    owner_identity = workspace.personal? ? workspace.owner&.identity : nil

    if identity.image?
      render_workspace_logo(identity, size)
    elsif owner_identity&.source == "upload" && owner_identity.image?
      render_owner_avatar_fallback(workspace, size)
    else
      render_workspace_initials(identity, size)
    end
  end

  private

  # Recency then name — the same ordering #workspaces_by_recency applies to the
  # switch list, done in SQL so a solo user's single workspace isn't loaded
  # through the switcher's eager-load chain just to pick a default.
  def last_accessed_workspace
    Current.user.workspaces.kept
           .order(Membership.arel_table[:last_accessed_at].desc.nulls_last, :name)
           .first
  end

  def render_workspace_logo(identity, size)
    px = AvatarHelper::AVATAR_SIZES.fetch(size)[:px]
    # main_app.url_for is required because the shared header / workspace
    # switcher render inside the markdowndocs engine layout too — and
    # `image_tag variant` from a non-main-app context fails (Active Storage
    # routes live on main_app, not engine routers). See avatar_helper for
    # the same fix; same pattern, same reason.
    src = main_app.url_for(identity.image.variant(resize_to_fill: [ px, px ]))
    # src + fallback together arm the component's broken-image swap — a logo
    # that 404s renders initials instead of a broken image.
    render UI::AvatarComponent.new(
      src: src, fallback: identity.initials, hue: identity.hue, size: size
    )
  end

  def render_owner_avatar_fallback(workspace, size)
    avatar_for(workspace.owner, size: size)
  end

  # hue: is always explicit here (Identity#hue defaults to DEFAULT_HUE), unlike
  # avatar_helper, which passes nil at the default so the component's
  # bg-interactive branch applies. Parity with the pre-component workspace
  # markup; picking one behavior for both helpers is a tracked follow-up.
  def render_workspace_initials(identity, size)
    render UI::AvatarComponent.new(fallback: identity.initials, hue: identity.hue, size: size)
  end
end
