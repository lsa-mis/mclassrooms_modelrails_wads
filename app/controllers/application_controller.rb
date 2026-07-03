class ApplicationController < ActionController::Base
  include Authenticatable
  include RequiresOnboarding
  include Pundit::Authorization
  include Toastable
  include Pagy::Method
  include SettingsContext
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from Suspendable::SuspendedError, with: :workspace_locked

  helper_method :signups_open?

  def signups_open?
    return @signups_open if defined?(@signups_open)

    @signups_open = SignupPolicy.allows_signup?(
      invitation_token: session[:pending_invitation_token],
      join_token: session[:pending_join_token]
    )
  end

  private

  # Backs Pundit's pundit_user and is consumed by mounted engines (e.g.
  # markdowndocs) — keep it even though app code should prefer Current.user.
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

  def workspace_locked
    redirect_to workspaces_path, alert: t("workspaces.locked_notice")
  end

  # Maps a Passkeys::Error subclass to its localized message for JSON error responses.
  def passkey_error_message(error)
    key = case error
    when Passkeys::ChallengeExpired           then "challenge_expired"
    when Passkeys::CredentialNotFound         then "credential_not_found"
    when Passkeys::CredentialAlreadyRegistered then "credential_already_registered"
    when Passkeys::ClonedAuthenticator        then "cloned_authenticator"
    when Passkeys::VerificationFailed         then "verification_failed"
    else                                           "unknown"
    end
    t("passkeys.errors.#{key}")
  end
end
