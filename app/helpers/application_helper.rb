module ApplicationHelper
  include Pagy::Method

  def current_user_theme
    cookies[:theme].presence || Current.user&.preferences&.theme || "system"
  end

  # Names trusted-HTML output explicitly so herb-lint's `erb-no-unsafe-raw`
  # rule does not flag every callsite. Use only with content the app itself
  # produced and rendered (e.g. markdown rendered server-side by the
  # markdowndocs gem). Never pass user-supplied raw HTML.
  def safe_html(content)
    content&.html_safe
  end

  # Returns the scoped, eager-loaded workspaces relation used by the workspace
  # sidebar switcher (application.html.erb) and settings sidebar (settings.html.erb).
  #
  # :logo_attachment is always eager-loaded — required by the switcher icon on
  # every row regardless of posture.
  #
  # `memberships: [:role, { user: :avatar_attachment }]` is included ONLY under
  # the :personal posture, where workspace_icon_for may fall back to the personal
  # workspace owner's avatar. Under :none there are no personal workspaces, so
  # walking memberships would be dead weight on every authenticated page.
  def sidebar_workspaces_scope
    base = Current.user.workspaces.kept.includes(:logo_attachment)

    if TenancyConfig.personal?
      base.includes(memberships: [ :role, { user: :avatar_attachment } ])
    else
      base
    end
  end
end
