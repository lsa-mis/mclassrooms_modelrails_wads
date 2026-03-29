module ApplicationHelper
  def current_user_theme
    cookies[:theme].presence || Current.user&.preferences&.theme || "system"
  end
end
