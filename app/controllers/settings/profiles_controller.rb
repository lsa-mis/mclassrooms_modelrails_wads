module Settings
  class ProfilesController < ApplicationController
    layout "settings"

    # Changing your email is a factor change — confirm identity first. This
    # replaces the old current-password gate, which locked passwordless users
    # out of email changes entirely.
    before_action :require_reauthentication!, only: :update, if: :email_change_requested?

    def edit
      @user = Current.user
      authorize @user, policy_class: Settings::ProfilePolicy
    end

    def update
      @user = Current.user
      authorize @user, policy_class: Settings::ProfilePolicy

      if email_change_requested?
        handle_email_change
      else
        handle_profile_update
      end
    end

    private

    def profile_params
      params.require(:user).permit(:first_name, :last_name, :email_address)
    end

    def email_change_requested?
      new_email = params.dig(:user, :email_address)
      new_email.present? && new_email.strip.downcase != Current.user.email_address
    end

    def handle_email_change
      name_attrs = profile_params.to_h.slice("first_name", "last_name").compact
      @user.assign_attributes(name_attrs) if name_attrs.any?

      if Users::EmailChange.new(@user).initiate!(profile_params[:email_address])
        @user.save! if @user.changed?
        AuthenticationMailer.email_change_verification(@user).deliver_later
        AuthenticationMailer.email_change_notification(@user).deliver_later
        redirect_to edit_settings_profile_path, notice: t("settings.profiles.update.verification_sent", email: @user.pending_email)
      else
        @user.errors.add(:email_address, t("settings.profiles.update.email_unchanged"))
        render :edit, status: :unprocessable_entity
      end
    end

    def handle_profile_update
      if @user.update(profile_params.except(:email_address))
        redirect_to edit_settings_profile_path, notice: t("settings.profiles.update.success")
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
