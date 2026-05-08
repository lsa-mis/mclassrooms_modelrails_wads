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
end
