module WorkspaceSwitcherHelper
  # Workspaces shown in the header context switcher, preloaded for the chip
  # (logo + role), N+1-safe. Memoized so the desktop and mobile switcher
  # variants share one load.
  # Recency ordering is applied at render time via #workspaces_by_recency (not
  # here) so a solo user's single workspace isn't force-loaded just to be sorted.
  def switcher_workspaces
    @switcher_workspaces ||= Current.user.workspaces.kept.includes(:logo_attachment, memberships: :role)
  end

  # Capped: current workspace pinned, at most five, so the phone list fits (#1091).
  def switcher_menu_workspaces(workspaces, current:, capped:)
    return workspaces unless capped

    pinned = [ current ].compact
    rest = workspaces_by_recency(workspaces).reject { |w| current && w.id == current.id }
    (pinned + rest).first(5)
  end

  # Most-recent access first; call only inside the 2+ workspaces branch (Bullet).
  def workspaces_by_recency(workspaces)
    workspaces.sort_by do |workspace|
      accessed = workspace.memberships.detect { |m| m.user_id == Current.user.id }&.last_accessed_at
      [ accessed ? 0 : 1, accessed ? -accessed.to_i : 0, workspace.name.downcase ]
    end
  end
end
