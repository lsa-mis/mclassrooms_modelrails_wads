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
  # What the switcher menu actually lists. Capped, the phone copy pins the
  # current workspace first and shows at most five (the hamburger's old bound),
  # so a long list cannot run the dropdown off a 375px screen — "All workspaces"
  # below it is the overflow. Uncapped, the collection passes through.
  #
  # Extracted from the partial so the cap and the recency order can be tested at
  # all: as a line inside the view they had no reachable seam, and every request
  # example ran with two workspaces, where the cap is a no-op (#1091).
  def switcher_menu_workspaces(workspaces, current:, capped:)
    return workspaces unless capped

    pinned = [ current ].compact
    rest = workspaces_by_recency(workspaces).reject { |w| current && w.id == current.id }
    (pinned + rest).first(5)
  end

  def workspaces_by_recency(workspaces)
    workspaces.sort_by do |workspace|
      accessed = workspace.memberships.detect { |m| m.user_id == Current.user.id }&.last_accessed_at
      [ accessed ? 0 : 1, accessed ? -accessed.to_i : 0, workspace.name.downcase ]
    end
  end
end
