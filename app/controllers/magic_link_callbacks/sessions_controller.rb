module MagicLinkCallbacks
  # The state-changing half of a magic-link sign-in (SEC-5): the confirmation
  # page's button POSTs here, the token is spent, the session starts. The GET
  # on the callback itself only renders that confirmation.
  class SessionsController < ApplicationController
    allow_unauthenticated_access

    def create
      # Consume first, then branch: a sign-in POST for an address with no account
      # is misuse (the confirm page sends unknown addresses to the registration
      # create), so the token is spent either way (#954).
      token_record = MagicLinkToken.consume!(token)
      user = token_record && User.find_by(email_address: token_record.email)

      unless user
        if (replayed = replayed_sign_in)
          # Not a failure: this browser is signed in as the address the token
          # belongs to, so the POST that spent it is the one that signed them in.
          # Answering "invalid or has expired" here tells a signed-in user the
          # opposite of what just happened (#846).
          redirect_to magic_link_return_path(replayed), notice: t("magic_link_callbacks.show.signed_in")
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

    # The spent token this same browser already redeemed, or nil.
    #
    # A second POST of one token is ordinary: a double-clicked confirm button, a
    # browser retrying a POST, a driver re-dispatching a click on a loaded CI
    # shard. `consume!` is single-use, so the replay comes back nil and looks
    # exactly like an expired link — except the session the first POST created is
    # live, which no expiry and no superseding mint can produce.
    #
    # Matching on the address is the fence: only the owner may read a spent token
    # as their own replay. A signed-in visitor holding somebody else's used link
    # still gets the invalid alert, and no session is started either way.
    def replayed_sign_in
      return nil unless authenticated?

      spent = MagicLinkToken.find_by(token_digest: MagicLinkToken.digest(token))
      return nil if spent.nil? || spent.consumed_at.nil?

      spent if spent.email == Current.user.email_address
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
