class ApplicationController < ActionController::Base
  include Authenticatable
  include RequiresOnboarding
  include Pundit::Authorization
  include Toastable
  include Pagy::Method
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from Suspendable::SuspendedError, with: :workspace_locked
  rescue_from Workspace::NotAdmittableError, with: :not_admittable

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

  # Fork override of the template's authenticated-landing seam
  # (Authenticatable#authenticated_home_path): signing in drops a non-admin
  # straight into the product — Find a Room — ONCE, at authentication time.
  # Root itself never redirects (panel call, 2026-07-13: "where sign-in drops
  # you" and "what home is" are different decisions — the logo links to root,
  # and a link named for the site must mean the same thing for every role).
  # Same admittable gate DirectoryScoped applies to GET /find-a-room, so a
  # missing/personal-posture/suspended shared workspace falls back to the
  # landing instead of chaining through DirectoryScoped's own redirect.
  def authenticated_home_path
    resume_session
    workspace = TenancyConfig.shared_workspace # nil unless shared posture + kept workspace
    return root_path unless Current.user && workspace && !workspace.suspended?
    return root_path if RoleResolver.for(Current.user).admin? # admins keep the landing

    find_a_room_path
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

  # Generic, non-disclosing redirect for Workspace::NotAdmittableError — an
  # outsider following a join link/invitation must not learn whether the
  # workspace is archived, suspended, or deleted.
  def not_admittable
    redirect_to root_path, alert: t("workspaces.joins.invalid_or_revoked")
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
