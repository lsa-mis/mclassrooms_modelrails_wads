module Settings
  class ConnectedAccountsController < ApplicationController
    layout "settings"
    settings_context :identity

    allow_unauthenticated_access only: :verify

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

      # Claim any pending invitation that was persisted onto this Authentication
      # during unverified-email OAuth signup. A stale invitation (consumed by
      # someone else, expired, etc.) shouldn't block sign-in — surface as flash
      # but continue.
      begin
        auth.claim_pending_invitation!(Current.user)
      rescue Invitation::EmailMismatch
        flash[:alert] = t(".email_mismatch")
      rescue Invitation::NotAcceptable
        flash[:alert] = t("registrations.create.invitation_consumed")
      end

      # Reshape 2b: claim any pending workspace join-link token. Stale link
      # conditions (revoked, policy reverted) are silently no-op'd inside
      # claim_pending_join_link!; capacity errors propagate and we surface
      # them as a flash without blocking sign-in.
      begin
        auth.claim_pending_join_link!(Current.user)
      rescue ActiveRecord::RecordInvalid => e
        # "Already a member" is benign here — a pending invitation and a pending
        # join link can both resolve to the same workspace, so the second claim
        # is a harmless duplicate the success notice already covers. Only a real
        # blocker (capacity) warrants an alert, and it gets a localized message
        # rather than the raw model string. Mirrors Workspaces::JoinsController.
        # NOTE: this string-match coupling to Workspace#admit's messages is the
        # second call site; a third should trigger typed errors on #admit.
        unless e.message.match?(/already a member/i)
          flash[:alert] = t(".join_link_at_capacity")
        end
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
