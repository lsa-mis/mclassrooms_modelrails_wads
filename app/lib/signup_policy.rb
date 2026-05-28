class SignupPolicy
  def self.allows_signup?(token: nil)
    config_allows_signup? || invitation_acceptable?(token)
  end

  def self.config_allows_signup?
    Rails.configuration.x.signup.mode == :open
  end

  def self.invitation_acceptable?(token)
    return false if token.blank?

    !!Invitation.find_by(token: token)&.acceptable?
  end

  # Whether the instance permits a given per-workspace join strategy. The
  # operator's ceiling: Workspace#join_policy validation rejects strategies
  # not in this allowlist, and runtime guards (e.g. Workspace#open_join?)
  # check it as defense-in-depth.
  def self.permits_strategy?(strategy)
    Rails.configuration.x.signup.permitted_join_strategies.include?(strategy.to_sym)
  end
end
