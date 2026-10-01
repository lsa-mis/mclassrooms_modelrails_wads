module WorkspaceScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_workspace
    before_action :touch_membership_last_accessed
  end

  private

  def set_workspace
    slug = params[:workspace_slug] || params[:slug]
    @workspace = Current.user.workspaces.kept.find_by!(slug: slug)
    Current.workspace = @workspace
    session[:current_workspace_id] = @workspace.id
    # Locked gate. Redirect target MUST be workspaces_path — the nearest
    # existing pattern (user_not_authorized -> workspace_path) would
    # re-trigger this same gate in an infinite loop.
    redirect_to workspaces_path, alert: t("workspaces.locked_notice") if @workspace.suspended?
  rescue ActiveRecord::RecordNotFound
    redirect_to workspaces_path, alert: t("workspaces.not_found")
  end

  # At most one stamp per TOUCH_WINDOW (#171); a failed touch is reported, never raised.
  TOUCH_WINDOW = 5.minutes

  def touch_membership_last_accessed
    return unless Current.user && Current.workspace

    Membership
      .where(user_id: Current.user.id, workspace_id: Current.workspace.id, discarded_at: nil)
      .where("last_accessed_at IS NULL OR last_accessed_at < ?", TOUCH_WINDOW.ago)
      .update_all(last_accessed_at: Time.current)
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { touch_membership_for_user: Current.user&.id })
  end
end
