class ApplicationController < ActionController::Base
  include Authenticatable
  include Reauthenticatable
  include RequiresOnboarding
  include Pundit::Authorization
  include Toastable
  include Pagy::Method
  allow_browser versions: :modern

  stale_when_importmap_changes

  # Authenticated HTML must not be written to shared caches or the browser's
  # disk cache — it now carries the form-draft key meta (spec: key-surface
  # hardening). Trade-off accepted: this defeats HTML ETag revalidation for
  # signed-in users.
  after_action :prevent_authenticated_html_caching

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from Suspendable::SuspendedError, with: :workspace_locked
  rescue_from Workspace::NotAdmittableError, with: :not_admittable
  rescue_from User::SuspendedError, with: :user_suspended

  helper_method :signups_open?, :pending_join_workspace

  def signups_open?
    return @signups_open if defined?(@signups_open)

    @signups_open = SignupPolicy.allows_signup?(
      invitation_token: session[:pending_invitation_token],
      join_token: session[:pending_join_token]
    )
  end

  # A parked join token the user could use: offered as a banner, never a forced join.
  # Returns the link so the accepting write can re-check it (#1061).
  def pending_join_link
    return @pending_join_link if defined?(@pending_join_link)

    @pending_join_link = resolve_pending_join_link
  end

  def pending_join_workspace
    pending_join_link&.workspace
  end

  private

  def resolve_pending_join_link
    return nil unless Current.user

    token = session[:pending_join_token]
    return nil if token.blank?

    link = WorkspaceJoinLink.find_active(token)
    return nil unless link&.workspace&.joinable_by?(Current.user)

    link
  end

  # Backs Pundit's pundit_user and is consumed by mounted engines (e.g.
  # markdowndocs) — keep it even though app code should prefer Current.user.
  def current_user
    Current.user
  end

  # SEC-1: refuse to grant a role the actor doesn't outrank. The server is the
  # real gate; role selects render assignable_roles_for as defence + UX.
  def authorize_role_grant!(policy_record, role)
    return if policy(policy_record).may_grant?(role)

    log_blocked_role_grant(policy_record, role)
    raise Pundit::NotAuthorizedError
  end

  # G (SEC-1 follow-up): a blocked escalation attempt is itself a security
  # event — log the SPECIFIC denial to the admin feed (not every 403; generic
  # authorization failures stay unlogged). Best-effort, same contract as
  # Trackable#create_activity: tracking must never fail the request.
  def log_blocked_role_grant(policy_record, role)
    ActivityLog.create!(
      actor: Current.user,
      action: "membership.role_grant_blocked",
      trackable: policy_record.is_a?(ActiveRecord::Base) ? policy_record : nil,
      workspace: Current.workspace,
      visibility: "admin",
      metadata: { "attempted_role" => role.slug }
    )
  rescue StandardError => e
    Rails.logger.warn("Blocked-grant logging failed: #{e.class}: #{e.message}")
    Rails.error.report(e, handled: true, context: { action: "membership.role_grant_blocked" })
  end

  def assignable_roles_for(policy_record)
    Current.workspace.effective_roles.select { |role| policy(policy_record).may_grant?(role) }
  end

  # Fork seam: a non-admin lands on Find a Room once, at sign-in. See /docs/developer/rooms-directory (Landing and denials).
  def authenticated_home_path
    resume_session
    workspace = TenancyConfig.shared_workspace
    return root_path unless Current.user && workspace && !workspace.suspended?
    return root_path if RoleResolver.for(Current.user).admin?

    find_a_room_path
  end

  def prevent_authenticated_html_caching
    return unless Current.user && request.format.html?

    response.headers["Cache-Control"] = "no-store"
  end

  def user_not_authorized
    redirect_to(not_authorized_redirect_path, alert: t("errors.not_authorized"))
  end

  # Every branch must be loop-safe (#931, SEC-10). See /docs/developer/rooms-directory (Landing and denials).
  def not_authorized_redirect_path
    return url_from(request.referer) || root_path if Current.workspace.blank?

    if policy(Current.workspace).show?
      workspace_home = workspace_path(Current.workspace)
      return request.path == workspace_home ? workspaces_path : workspace_home
    end

    return find_a_room_path if Current.user && RoleResolver.for(Current.user).viewer?

    root_path
  end

  def record_not_found
    respond_to do |format|
      format.turbo_stream { render turbo_stream: error_toast(t("errors.not_found")), status: :not_found }
      format.html { redirect_to(url_from(request.referer) || root_path, alert: t("errors.not_found")) }
      format.json { render json: { error: t("errors.not_found") }, status: :not_found }
      format.any { head :not_found }
    end
  end

  def workspace_locked
    redirect_to workspaces_path, alert: t("workspaces.locked_notice")
  end

  def user_suspended
    respond_to do |format|
      format.html { redirect_to new_session_path, alert: t("sessions.create.suspended") }
      format.json { render json: { error: t("sessions.create.suspended") }, status: :forbidden }
      format.any { head :forbidden }
    end
  end

  # Generic, non-disclosing redirect for Workspace::NotAdmittableError — an
  # outsider following a join link/invitation must not learn whether the
  # workspace is archived, suspended, or deleted.
  def not_admittable
    redirect_to root_path, alert: t("workspaces.joins.invalid_or_revoked")
  end
end
