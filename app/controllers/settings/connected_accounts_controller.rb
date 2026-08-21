module Settings
  class ConnectedAccountsController < ApplicationController
    before_action :require_reauthentication!, only: :destroy
    layout "settings"

    allow_unauthenticated_access only: :verify

    # Verification-time rendering of PendingClaims problems.
    CLAIM_PROBLEM_MESSAGES = {
      invitation_email_mismatch: "settings.connected_accounts.verify.email_mismatch",
      invitation_consumed: "registrations.create.invitation_consumed",
      join_link_at_capacity: "settings.connected_accounts.verify.join_link_at_capacity"
    }.freeze

    rate_limit to: 3, within: 3.minutes, only: :resend_verification,
      by: -> { Current.user&.id || request.remote_ip },
      with: -> {
        redirect_to settings_connected_accounts_path,
          alert: t("settings.connected_accounts.resend_verification.rate_limited")
      }

    def index
      @authentications = Current.user.authentications
    end

    def verify
      auth = Authentication.find_by_token_for(:email_verification, params[:token])

      if auth.nil?
        redirect_to(authenticated? ? settings_connected_accounts_path : new_session_path,
                    alert: t(".invalid_or_expired"))
        return
      end

      # Cross-user case reuses invalid_or_expired flash deliberately:
      # never confirm or deny that a token belongs to a different account.
      if authenticated? && Current.user.id != auth.user_id
        redirect_to settings_connected_accounts_path,
          alert: t(".invalid_or_expired")
        return
      end

      was_authenticated = authenticated?

      auth.verify!

      # For unauthenticated callers verifying their first auth (new-user OAuth
      # unverified-email flow from Task 8), sign them in now that their email
      # is proven. This is a one-shot sign-in tied to email verification.
      start_new_session_for(auth.user) unless was_authenticated

      # Claim whatever was parked on this Authentication during unverified-email
      # OAuth signup (invitation token + join-link digest). Continue semantics:
      # a stale claim shouldn't block sign-in — problems surface as flash. The
      # exception matrix lives in PendingClaims; only the copy is chosen here
      # (deliberately different wording from the signup-time site, which speaks
      # to a signed-in user rather than a just-verified one).
      problems = auth.claim_pending!(Current.user).problems
      if problems.any?
        flash[:alert] = problems.map { |problem| t(CLAIM_PROBLEM_MESSAGES.fetch(problem)) }.join(" ")
      end

      if was_authenticated
        redirect_to settings_connected_accounts_path,
          notice: t(".success", provider: auth.display_provider)
      else
        redirect_to root_path, notice: t(".success", provider: auth.display_provider)
      end
    end

    def resend_verification
      auth = Current.user.authentications.find(params[:id])

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
        redirect_to settings_connected_accounts_path,
          notice: t(".success", provider: destroyed_auth.display_provider)
      else
        redirect_to settings_connected_accounts_path,
          alert: t(".cannot_remove_last_verified")
      end
    end
  end
end
