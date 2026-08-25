module Settings
  class PasswordsController < ApplicationController
    layout "settings"

    before_action :require_reauthentication!, only: [ :create, :update, :destroy ]

    def new
      redirect_to edit_settings_password_path if Current.user.has_password?
    end

    def create
      if Current.user.has_password?
        redirect_to edit_settings_password_path, alert: t(".already_has_password")
        return
      end

      if update_password_with_precheck
        Current.user.authentications.create!(
          provider: "email",
          uid: Current.user.email_address,
          verified_at: Time.current
        )
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

      if update_password_with_precheck
        revoke_other_sessions
        redirect_to settings_connected_accounts_path, notice: t(".success")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      Current.user.authentications.email.destroy_all
      Current.user.update_columns(password_digest: nil)
      revoke_other_sessions
      redirect_to settings_connected_accounts_path, notice: t(".success")
    end

    private

    # Changing or removing a credential signs out every other device — a
    # stolen session shouldn't survive the owner rotating their password.
    def revoke_other_sessions
      Current.user.sessions.where.not(id: Current.session.id).delete_all
    end

    def password_params
      params.require(:user).permit(:password, :password_confirmation)
    end

    # Assign → precheck → save, so the HIBP range check (network I/O) runs
    # OUTSIDE the write transaction and the validation consumes the memo (#674).
    def update_password_with_precheck
      Current.user.assign_attributes(password_params)
      Current.user.precheck_password_pwned!
      Current.user.save
    end
  end
end
