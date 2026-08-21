class SignupPolicy
  # The signup gate opens when ANY of three conditions hold: the instance
  # is in :open mode, OR the caller has a valid pending invitation token,
  # OR the caller has a valid workspace join-link token (Reshape 2b).
  # Both token kwargs are independently optional — composable.
  def self.allows_signup?(invitation_token: nil, join_token: nil)
    config_allows_signup? ||
      invitation_acceptable?(invitation_token) ||
      workspace_join_acceptable?(join_token)
  end

  def self.config_allows_signup?
    Rails.configuration.x.signup.mode == :open
  end

  def self.invitation_acceptable?(token)
    return false if token.blank?

    !!Invitation.find_by(token: token)&.acceptable?
  end

  # Reshape 2b: a workspace join link opens the signup gate iff the link is
  # active AND the workspace's join_policy is :open_link AND personal
  # workspaces are excluded AND the instance allowlist permits :open_link.
  # The composed check lives on Workspace#open_join? — reuse it rather than
  # restating the rules here.
  def self.workspace_join_acceptable?(token)
    return false if token.blank?

    link = WorkspaceJoinLink.find_active(token)
    return false if link.nil?
    link.workspace.open_join?
  end

  # Whether the instance permits a given per-workspace join strategy. The
  # operator's ceiling: Workspace#join_policy validation rejects strategies
  # not in this allowlist, and runtime guards (e.g. Workspace#open_join?)
  # check it as defense-in-depth.
  def self.permits_strategy?(strategy)
    Rails.configuration.x.signup.permitted_join_strategies.include?(strategy.to_sym)
  end

  # The three OR-branches are implementation detail of allows_signup? — the
  # public API is allows_signup? + permits_strategy? only.
  private_class_method :config_allows_signup?, :invitation_acceptable?, :workspace_join_acceptable?
end
