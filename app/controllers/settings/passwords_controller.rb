module Settings
  class PasswordsController < ApplicationController
    layout "settings"

    before_action :require_reauthentication!, only: [ :create, :update, :destroy ]
    # Every credential mutation shares one budget, matching the sibling
    # settings controllers (#819). Each mutation writes an ActivityLog row
    # retained under the 365-day security floor, so the endpoint has a durable
    # side effect per request.
    rate_limit to: 10, within: 3.minutes, only: [ :create, :update, :destroy ],
      with: -> { redirect_to settings_connected_accounts_path, alert: t("settings.passwords.rate_limited") }

    def new
      redirect_to edit_settings_password_path if Current.user.has_password?
    end

    def create
      if Current.user.has_password?
        redirect_to edit_settings_password_path, alert: t(".already_has_password")
        return
      end

      # The block runs inside the password save's transaction: a first
      # password and its email authentication commit as one unit, the same
      # shape #destroy already has (#821).
      if update_password_with_precheck { ensure_pending_email_authentication! }
        redirect_to settings_connected_accounts_path, notice: t(".success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      redirect_to new_settings_password_path unless Current.user.has_password?
    end

    def update
      unless Current.user.has_password?
        redirect_to new_settings_password_path
        return
      end

      if update_password_with_precheck(revoke_others: true)
        redirect_to settings_connected_accounts_path, notice: t(".success")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      # Auth teardown, digest clear, and session revocation commit as one unit —
      # the block runs inside remove_password!'s transaction. Idempotent under a
      # concurrent double-submit: the second caller re-reads, finds the digest
      # already gone, and does nothing. Either way the user's password is gone,
      # so both get the same answer.
      Current.user.remove_password! { revoke_other_sessions }
      redirect_to settings_connected_accounts_path, notice: t(".success")
    end

    private

    # Changing or removing a credential signs out every other device — a
    # stolen session shouldn't survive the owner rotating their password.
    def revoke_other_sessions
      Current.user.sessions.where.not(id: Current.session.id).delete_all
    end

    # PENDING, not verified: setting a password proves control of this
    # session, not of the mailbox. Stamping verified_at here let password-set
    # alone satisfy User#can_invite? with no email round trip; the user now
    # sees the standard verify-your-email prompt, which is the truth.
    #
    # The finder is keyed on provider ALONE — the unique index is
    # (user_id, provider), and a finder that also keyed on uid missed the
    # existing row whenever the address had changed underneath it, then
    # attempted a duplicate (#865). Finding the row never downgrades one that
    # is already verified; uid stays whatever the email-change sync last wrote.
    def ensure_pending_email_authentication!
      Current.user.authentications.find_or_create_by!(provider: "email") do |auth|
        auth.uid = Current.user.email_address
      end
    end

    def password_params
      params.require(:user).permit(:password, :password_confirmation)
    end

    # Assign → precheck → save, so the HIBP range check (network I/O) runs
    # OUTSIDE the write transaction and the validation consumes the memo (#674)
    # — fenced by the request spec's transaction-depth assertion.
    # With revoke_others, the save and the revocation share one transaction:
    # credential rotation and stolen-session death commit atomically.
    def update_password_with_precheck(revoke_others: false)
      Current.user.assign_attributes(password_params)
      Current.user.precheck_password_pwned!
      ApplicationRecord.transaction do
        Current.user.save.tap do |saved|
          if saved
            revoke_other_sessions if revoke_others
            yield if block_given?
          end
        end
      end
    end
  end
end
