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

  # Navigation IA (Task 10): the single grant consulted to gate admin-only
  # nav/UI. Memoized per request — a signed-in request can render the same
  # admin check on both the desktop and mobile nav, and RoleResolver.for
  # deliberately re-reads the DB every call (see app/lib/role_resolver.rb),
  # so memoizing here (not in RoleResolver itself) keeps that freshness
  # guarantee for callers who genuinely want a fresh read while still
  # avoiding duplicate queries within a single view render.
  #
  # No nil-guard needed for a signed-out Current.user: RoleResolver.for(nil)
  # already resolves to an all-false Grant (Membership#find_by(user: nil)
  # matches no row), so this helper is safe to call unconditionally from
  # views — the phase 4/5 admin views this unlocks can do the same.
  def current_grant
    @current_grant ||= RoleResolver.for(Current.user)
  end
end
