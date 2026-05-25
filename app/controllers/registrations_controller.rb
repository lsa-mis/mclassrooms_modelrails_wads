class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  require_unauthenticated_access only: :new
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_registration_path, alert: t("registrations.create.rate_limited") }

  def new
    if signups_open?
      @user = User.new
    else
      render :closed
    end
  end

  def create
    unless signups_open?
      render :closed, status: :unprocessable_entity
      return
    end

    @user = User.new(registration_params)
    authentication = nil

    begin
      ActiveRecord::Base.transaction do
        @user.save!
        authentication = @user.authentications.create!(
          provider: "email",
          uid: @user.email_address
        )
        authentication.generate_verification_token!
        accept_pending_invitation!(@user)
      end
    rescue ActiveRecord::RecordInvalid => e
      if e.record.is_a?(Invitation)
        flash.now[:alert] = t(".invitation_consumed")
      end
      render :new, status: :unprocessable_entity
      return
    end

    # Transaction committed. Side effects that must run AFTER commit:
    AuthenticationMailer.verification_email(authentication).deliver_later
    start_new_session_for(@user)
    redirect_to root_path, notice: t(".success")
  end

  private

  def registration_params
    params.require(:user).permit(
      :email_address, :first_name, :last_name,
      :password, :password_confirmation
    )
  end

  def accept_pending_invitation!(user)
    token = session.delete(:pending_invitation_token)
    return if token.blank?

    invitation = Invitation.find_by(token: token)
    invitation&.accept!(user)
  end
end
