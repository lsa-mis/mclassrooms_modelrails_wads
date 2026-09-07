module Settings
  class ConnectedAccountVerificationsController < ApplicationController
    allow_unauthenticated_access

    # Verification-time rendering of PendingClaims problems.
    CLAIM_PROBLEM_MESSAGES = {
      invitation_email_mismatch: "settings.connected_accounts.verify.email_mismatch",
      invitation_consumed: "registrations.create.invitation_consumed",
      join_link_at_capacity: "settings.connected_accounts.verify.join_link_at_capacity"
    }.freeze

    # Confirmation only: a mail scanner or prefetcher doing a bare GET must not
    # verify anything, and must not sign anyone in (#950). The POST below is
    # what verifies. Also reached via the legacy path-token route.
    def show
      @authentication = Authentication.find_by_token_for(:email_verification, params[:token])

      if @authentication.nil?
        redirect_to(authenticated? ? settings_connected_accounts_path : new_session_path,
                    alert: t(".invalid_or_expired"))
        return
      end

      # Cross-user case reuses invalid_or_expired flash deliberately:
      # never confirm or deny that a token belongs to a different account.
      if authenticated? && Current.user.id != @authentication.user_id
        redirect_to settings_connected_accounts_path, alert: t(".invalid_or_expired")
        return
      end

      @token = params[:token]
    end

    def create
      auth = Authentication.find_by_token_for(:email_verification, params[:token])

      if auth.nil?
        redirect_to(authenticated? ? settings_connected_accounts_path : new_session_path,
                    alert: t("settings.connected_account_verifications.show.invalid_or_expired"))
        return
      end

      # Cross-user case reuses invalid_or_expired flash deliberately:
      # never confirm or deny that a token belongs to a different account.
      if authenticated? && Current.user.id != auth.user_id
        redirect_to settings_connected_accounts_path,
          alert: t("settings.connected_account_verifications.show.invalid_or_expired")
        return
      end

      was_authenticated = authenticated?

      # verify! is a compare-and-swap (#950): a concurrent POST for the same
      # token can win the race and leave this one with false even though the
      # token decoded fine above.
      unless auth.verify!
        redirect_to(authenticated? ? settings_connected_accounts_path : new_session_path,
                    alert: t("settings.connected_account_verifications.show.invalid_or_expired"))
        return
      end

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

      # Outcome in the document (#950): the index is where the confirmation
      # shows, even for the unauthenticated-caller path that used to land on
      # root — flash[:verified_email] drives the success banner there.
      flash[:verified_email] = auth.email
      redirect_to settings_connected_accounts_path, notice: t(".success", provider: auth.display_provider)
    end
  end
end
