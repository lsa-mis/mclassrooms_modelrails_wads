module Account
  class ConnectedAccountsController < ApplicationController
    allow_unauthenticated_access only: :verify

    rate_limit to: 3, within: 3.minutes, only: :resend_verification,
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

      auth.verify!

      if authenticated?
        redirect_to account_connected_accounts_path,
          notice: t(".success", provider: auth.provider.titleize)
      else
        redirect_to new_session_path,
          notice: t(".success_signed_out", provider: auth.provider.titleize)
      end
    end

    def resend_verification
      auth = Current.user.authentications.find(params[:id])

      if auth.pending?
        auth.generate_verification_token!
        AuthenticationMailer.link_verification_email(auth).deliver_later
        redirect_to account_connected_accounts_path,
          notice: t(".resent", email: auth.email)
      else
        redirect_to account_connected_accounts_path,
          alert: t(".not_pending")
      end
    end

    def destroy
      authentication = Current.user.authentications.find(params[:id])

      if Current.user.authentications.count <= 1
        redirect_to account_connected_accounts_path,
          alert: t(".last_method")
      else
        authentication.destroy!
        redirect_to account_connected_accounts_path,
          notice: t(".success", provider: authentication.provider.titleize)
      end
    end
  end
end
