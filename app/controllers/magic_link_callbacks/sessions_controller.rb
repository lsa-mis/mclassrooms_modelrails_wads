module MagicLinkCallbacks
  # The state-changing half of a magic-link sign-in (SEC-5): the confirmation
  # page's button POSTs here, the token is spent, the session starts. The GET
  # on the callback itself only renders that confirmation.
  class SessionsController < ApplicationController
    include MagicLinkReplayable

    allow_unauthenticated_access

    def create
      # Consume first, then branch: a sign-in POST for an address with no account
      # is misuse (the confirm page sends unknown addresses to the registration
      # create), so the token is spent either way (#954).
      token_record = MagicLinkToken.consume!(token)
      user = token_record && User.find_by(email_address: token_record.email)

      unless user
        if replayed_sign_in
          # Not a failure: this browser is signed in as the address the token
          # belongs to. Answering "invalid or has expired" tells a signed-in
          # user the opposite of what just happened (#846).
          #
          # The same answer the GET callback has always given, and deliberately
          # NOT the spent token's intent: `consumed_at` is written by
          # superseding as well as by redemption, so a "spent" token may be one
          # the user never clicked (#1083). Routing them to "set your password"
          # on the strength of an ignored link states something that did not
          # happen. A real redemption still honours its intent below.
          redirect_to authenticated_home_path, notice: t("authentication.already_signed_in")
          return
        end

        redirect_to(authenticated? ? root_path : new_session_path, alert: t("magic_link_callbacks.show.invalid"))
        return
      end

      start_new_session_for(user)
      redirect_to magic_link_return_path(token_record), notice: t("magic_link_callbacks.show.signed_in")
    end

    private

    def token
      params[:magic_link_callback_token]
    end

    # The spent token this same browser already redeemed, or nil — the
    # rationale and the address fence live on MagicLinkReplayable, shared with
    # the registration callback. Passed this controller's own `token` because
    # the two controllers name the param differently.
    def replayed_sign_in
      replayed_by_owner(token)
    end

    # Server-side intent → fixed path. Never trust a user-supplied URL here.
    def magic_link_return_path(token_record)
      case token_record.intent
      when "set_password" then edit_settings_password_path
      else after_authentication_url
      end
    end
  end
end
