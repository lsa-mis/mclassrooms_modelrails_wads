module Settings
  module ConnectedAccounts
    # A fresh verification email for a pending connected account. Scoped to
    # Current.user's own authentications, so no Pundit query is needed.
    class VerificationResendsController < ApplicationController
      rate_limit to: 3, within: 3.minutes, only: :create,
        by: -> { Current.user&.id || request.remote_ip },
        with: -> {
          redirect_to settings_connected_accounts_path,
            alert: t("settings.connected_accounts.verification_resends.create.rate_limited")
        }

      def create
        auth = Current.user.authentications.find(params[:connected_account_id])

        if auth.verified?
          redirect_to settings_connected_accounts_path,
            alert: t(".already_verified")
        else
          if EmailRecipientThrottle.allow!(auth.email, kind: :verification)
            AuthenticationMailer.link_verification_email(auth).deliver_later
          end
          redirect_to settings_connected_accounts_path,
            notice: t(".resent", email: auth.email)
        end
      end
    end
  end
end
