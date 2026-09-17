module WorkspaceSwitcherHelper
  # Workspaces shown in the header context switcher, preloaded for the chip
  # (logo + role), N+1-safe. Memoized so the desktop and mobile switcher
  # variants share one load.
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
end
