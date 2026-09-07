module Sessions
  # The email-first step of signing in: look the address up, send the right
  # magic link (sign-in or registration), and render the next step inline in
  # the sign_in_form frame. The password step is Sessions::PasswordsController.
  class LookupsController < ApplicationController
    allow_unauthenticated_access
    rate_limit to: 10, within: 3.minutes, only: :create,
      with: -> { redirect_to new_session_path, alert: t("sessions.create.rate_limited") }

    def create
      @email_lookup = EmailLookup.new(email_address: params[:email_address])

      unless @email_lookup.valid?
        render :email_error
        return
      end

      email = @email_lookup.email_address
      user = User.find_by(email_address: email)

      if user
        deliver_magic_link(user.email_address)
        @email_address = email
        @has_password = user.has_password?
        render :check_email
      else
        unless signups_open?
          render :closed, status: :unprocessable_entity
          return
        end
        deliver_magic_link(email, registration: true)
        @email_address = email
        render :check_email
      end
    end

    private

    # Recipient throttle (SEC-9): a throttled request renders the exact same
    # response WITHOUT touching the token table — skipping create_for_email is
    # what keeps an attacker from superseding the link the real user is
    # mid-click on. No leakage either way.
    def deliver_magic_link(email, registration: false)
      return unless EmailRecipientThrottle.allow!(email, kind: :magic_link)

      token = MagicLinkToken.create_for_email(email)
      return unless token

      if registration
        MagicLinkMailer.registration_link(email, token).deliver_later
      else
        MagicLinkMailer.sign_in_link(email, token).deliver_later
      end
    end
  end
end
