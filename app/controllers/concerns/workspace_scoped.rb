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

  # Stamps `memberships.last_accessed_at = NOW` for the (current user,
  # current workspace) pair on every workspace-scoped request. Powers the
  # "most-recently-accessed" sort + pinned-current row on workspaces#index.
  #
  # At most one UPDATE per five-minute window — no callback cascade, no
  # validations, no broadcasts. Silently swallows failures via Rails.error.report
  # so a connection blip on the touch doesn't 500 the user's page. Same posture
  # as NotificationBroadcaster#safe_broadcast (lib/notification_broadcaster.rb).
  #
  # The staleness predicate is the whole point: unguarded this wrote on every
  # workspace-scoped request across 20 controllers, which is a WAL page per page
  # load on a single-writer database. Measured, a guarded no-op UPDATE appends
  # zero WAL bytes and keeps the same index plan. Every reader of this stamp —
  # the workspaces sort, the row's "last seen" phrasing, the switcher's recency
  # order — tolerates minute granularity, so five minutes costs them nothing.
  # Not the Rails.cache debounce the issue proposed: Solid Cache is another
  # SQLite database, which moves the query rather than removing it (#171).
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
