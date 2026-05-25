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
end
