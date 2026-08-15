class PasswordResetsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: t("sessions.create.rate_limited") }

  def create
    email = params[:email_address].to_s.downcase.strip
    user = User.find_by(email_address: email)

    # Always show the same confirmation — never reveal whether the address
    # exists or has a password. Only a real password-holder gets a link.
    # Recipient throttle (SEC-9): shared :magic_link bucket — reset tokens live
    # in the same intent-blind supersede pool as sign-in links.
    if user&.has_password? && EmailRecipientThrottle.allow!(user.email_address, kind: :magic_link)
      token = MagicLinkToken.create_for_email(user.email_address, intent: "set_password")
      MagicLinkMailer.sign_in_link(user.email_address, token).deliver_later if token
    end

    @email_address = email
    render "sessions/check_email"
  end
end
