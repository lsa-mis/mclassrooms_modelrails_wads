module SettingsNavigationHelper
  # Renders a sidebar nav block only when the given Pundit policy permits the
  # action. By consulting the *same* policy/action the destination controller
  # authorizes against, we keep sidebar visibility and controller authorization
  # in lockstep — no separate SidebarPolicy to drift from the source of truth.
  #
  # Pass policy_class: when the record has more than one scoped policy and the
  # convention-inferred one isn't the gate to consult — e.g. a Workspace is
  # authorized by Workspaces::SettingsPolicy / Workspaces::ProfilePolicy rather
  # than the default WorkspacePolicy for those destinations.
  def render_nav_item_if_permitted(record, action:, policy_class: nil, &block)
    return nil unless block_given?

    policy = policy_class ? policy_class.new(Current.user, record) : Pundit.policy(Current.user, record)
    return nil unless policy.public_send(action)

    capture(&block)
  end

  # Returns a localized announcement string for the polite aria-live region
  # when a workspace context is active. The string interpolates the workspace
  # name, the viewer's role, and the list of sidebar items they can actually
  # see (so the announcement matches what's rendered). Returns nil for the
  # identity context and unauthenticated cases — the layout uses the
  # static identity template instead.
  def current_workspace_announcement_for_aria_live
    workspace = Current.workspace
    return nil if workspace.nil? || workspace.personal?

    membership = workspace.memberships.detect { |m| m.user_id == Current.user&.id }
    role_name = membership&.role&.name || Role.find_by(slug: "member", workspace_id: nil)&.name || "Member"

    I18n.t("settings.sidebar.aria_live_template.workspace",
           name: workspace.name,
           role: role_name,
           items: visible_workspace_sidebar_items.join(", "))
  end

  private

  # Builds the comma-joined list of workspace-sidebar item labels the current
  # user is authorized to see. Mirrors the policy gates in
  # _workspace_settings_sidebar_items so the aria-live announcement reflects
  # the rendered sidebar exactly.
  def visible_workspace_sidebar_items
    workspace = Current.workspace
    items = []

    if Workspaces::ProfilePolicy.new(Current.user, workspace).update?
      items << I18n.t("settings.sidebar.items.profile")
    end
    if Pundit.policy(Current.user, Membership.new(workspace: workspace)).index?
      items << I18n.t("settings.sidebar.items.members")
    end
    if Pundit.policy(Current.user, Invitation.new(invitable: workspace)).index?
      items << I18n.t("settings.sidebar.items.invitations")
    end
    if Workspaces::SettingsPolicy.new(Current.user, workspace).update?
      items << I18n.t("settings.sidebar.items.limits_and_plan")
    end

    items
  end
end
