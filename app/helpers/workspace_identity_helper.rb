module WorkspaceIdentityHelper
  # The VIEWER's role in a workspace, for the identity bar's subtitle. Reads
  # the signed-in user's own membership — not the workspace's first or owner
  # membership, which name the wrong person for everyone but the owner.
  # Returns nil for a signed-out request or a workspace the user has left,
  # and the bar simply omits the line.
  def current_user_role_in(workspace)
    return nil unless workspace && Current.user

    workspace.memberships.kept.find_by(user_id: Current.user.id)&.role
  end
end
