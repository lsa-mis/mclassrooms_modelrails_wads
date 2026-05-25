class ApplicationController < ActionController::Base
  include Authenticatable
  include Pundit::Authorization
  include Toastable
  include Pagy::Method
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  helper_method :signups_open?

  def signups_open?
    return @signups_open if defined?(@signups_open)

    @signups_open = SignupPolicy.allows_signup?(token: session[:pending_invitation_token])
  end

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

  def record_not_found
    respond_to do |format|
      format.turbo_stream { render turbo_stream: error_toast(t("errors.not_found")), status: :not_found }
      format.html { redirect_to(request.referer || root_path, alert: t("errors.not_found")) }
      format.json { render json: { error: t("errors.not_found") }, status: :not_found }
      format.any { head :not_found }
    end
  end
end
