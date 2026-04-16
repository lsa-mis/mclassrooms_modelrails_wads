module Account
  class ProfilesController < ApplicationController
    def edit
      @user = Current.user
      authorize @user, policy_class: Account::ProfilePolicy
    end

    def update
      @user = Current.user
      authorize @user, policy_class: Account::ProfilePolicy

      if email_change_requested?
        handle_email_change
      else
        handle_profile_update
      end
    end

    private

    def profile_params
      params.require(:user).permit(:first_name, :last_name, :email_address, :current_password)
    end

    def email_change_requested?
      new_email = profile_params[:email_address]
      new_email.present? && new_email.strip.downcase != @user.email_address
    end

    def handle_email_change
      current_password = profile_params[:current_password]
      new_email = profile_params[:email_address]

      if current_password.blank?
        @user.errors.add(:current_password, t(".password_required"))
        render :edit, status: :unprocessable_entity
        return
      end

      # Update name fields if included
      name_attrs = profile_params.to_h.slice("first_name", "last_name").compact
      @user.assign_attributes(name_attrs) if name_attrs.any?

      if @user.initiate_email_change!(new_email, current_password)
        @user.save! if @user.changed?
        AuthenticationMailer.email_change_verification(@user).deliver_later
        AuthenticationMailer.email_change_notification(@user).deliver_later
        redirect_to edit_account_profile_path, notice: t(".verification_sent", email: @user.pending_email)
      else
        @user.errors.add(:current_password, t(".wrong_password")) unless @user.errors[:current_password].any?
        render :edit, status: :unprocessable_entity
      end
    end

    def handle_profile_update
      update_params = profile_params.except(:email_address, :current_password)
      if @user.update(update_params)
        redirect_to edit_account_profile_path, notice: t(".success")
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
