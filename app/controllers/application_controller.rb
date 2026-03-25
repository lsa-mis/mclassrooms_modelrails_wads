class ApplicationController < ActionController::Base
  include Authenticatable
  include Pundit::Authorization
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def current_user
    Current.user
  end

  def user_not_authorized
    destination = if Current.workspace.present?
      workspace_path(Current.workspace)
    else
      request.referer || root_path
    end
    redirect_to(destination, alert: t("errors.not_authorized"))
  end
end
