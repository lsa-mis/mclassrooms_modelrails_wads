module WorkspaceSwitcherHelper
  # Workspaces shown in the header context switcher, preloaded for the chip
  # (logo + role), N+1-safe. Memoized so the banner and switcher share one load.
  # Recency ordering is applied at render time via #workspaces_by_recency (not
  # here) so a solo user's single workspace isn't force-loaded just to be sorted.
  def switcher_workspaces
    @switcher_workspaces ||= Current.user.workspaces.kept.includes(:logo_attachment, memberships: :role)
  end

  # Recency order for a loaded switcher collection (most-recent access first,
  # then alphabetical) so the capped mobile switch list shows the workspaces a
  # user would actually reach for, not an arbitrary DB order. Call INSIDE the
  # "2+ workspaces" render branch only — sorting materializes the relation, and
  # outside a render Bullet flags the icon includes as an unused eager-load.
  def workspaces_by_recency(workspaces)
    workspaces.sort_by do |workspace|
      accessed = workspace.memberships.detect { |m| m.user_id == Current.user.id }&.last_accessed_at
      [ accessed ? 0 : 1, accessed ? -accessed.to_i : 0, workspace.name.downcase ]
    end
  end

  # The workspace the switcher trigger reflects: the active one on a workspace
  # page, else the last-visited one remembered in the session (e.g. on /me),
  # else the most-recently-accessed membership. The last fallback covers the
  # first requests after login — start_new_session_for resets the session, so
  # session[:current_workspace_id] is empty until a workspace page is visited,
  # and without it the header rendered a blank switcher chip.
  def switcher_current_workspace
    Current.workspace ||
      Current.user.workspaces.kept.find_by(id: session[:current_workspace_id]) ||
      last_accessed_workspace
  end

  private

  # Recency then name — the same ordering #workspaces_by_recency applies to the
  # switch list, done in SQL so a solo user's single workspace isn't loaded
  # through the switcher's eager-load chain just to pick a default.
  def last_accessed_workspace
    Current.user.workspaces.kept
           .order(Membership.arel_table[:last_accessed_at].desc.nulls_last, :name)
           .first
  end
end
