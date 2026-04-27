module Account
  class ConnectedAccountsController < ApplicationController
    allow_unauthenticated_access only: :verify

    rate_limit to: 3, within: 3.minutes, only: :resend_verification,
      by: -> { Current.user&.id || request.remote_ip },
      with: -> {
        redirect_to account_connected_accounts_path,
          alert: t("account.connected_accounts.resend_verification.rate_limited")
      }

    def index
      @authentications = Current.user.authentications
    end

    def verify
      auth = Authentication.find_by(verification_token: params[:token])

      if auth.nil? || auth.token_expired?
        redirect_to(authenticated? ? account_connected_accounts_path : new_session_path,
                    alert: t(".invalid_or_expired"))
        return
      end

      # Cross-user case reuses invalid_or_expired flash deliberately:
      # never confirm or deny that a token belongs to a different account.
      if authenticated? && Current.user.id != auth.user_id
        redirect_to account_connected_accounts_path,
          alert: t(".invalid_or_expired")
        return
      end

      auth.verify!

      if authenticated?
        redirect_to account_connected_accounts_path,
          notice: t(".success", provider: auth.display_provider)
      else
        redirect_to new_session_path,
          notice: t(".success_signed_out", provider: auth.display_provider)
      end
    end

    def resend_verification
      auth = Current.user.authentications.find(params[:id])

      if auth.verified?
        redirect_to account_connected_accounts_path,
          alert: t(".already_verified")
      else
        auth.generate_verification_token!
        AuthenticationMailer.link_verification_email(auth).deliver_later
        redirect_to account_connected_accounts_path,
          notice: t(".resent", email: auth.email)
      end
    end

    def destroy
      destroyed_auth = nil

      destroyed = Authentication.transaction do
        # `.lock` issues SELECT FOR UPDATE on Postgres/MySQL. SQLite no-ops it,
        # but BEGIN IMMEDIATE (Rails default) gives database-wide write
        # serialization for the transaction's duration — same correctness.
        destroyed_auth = Current.user.authentications.lock.find(params[:id])

        if destroyed_auth.only_verified_remaining?
          false
        else
          destroyed_auth.destroy!
          true
        end
      end

      if destroyed
        redirect_to account_connected_accounts_path,
          notice: t(".success", provider: destroyed_auth.display_provider)
      else
        redirect_to account_connected_accounts_path,
          alert: t(".cannot_remove_last_verified")
      end
    end
  end
end
