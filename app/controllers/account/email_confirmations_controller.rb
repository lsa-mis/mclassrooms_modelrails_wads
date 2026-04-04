module Account
  class EmailConfirmationsController < ApplicationController
    def show
      if Current.user.confirm_email_change!(params[:token])
        redirect_to edit_account_profile_path, notice: t(".success")
      else
        redirect_to edit_account_profile_path, alert: t(".invalid_or_expired")
      end
    end

    def destroy
      Current.user.cancel_email_change!
      redirect_to edit_account_profile_path, notice: t(".cancelled")
    end
  end
end
