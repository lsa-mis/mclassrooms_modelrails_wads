class MagicLinkCallbacksController < ApplicationController
  allow_unauthenticated_access

  def show
    token_record = MagicLinkToken.find_valid(params[:token])
    unless token_record
      redirect_to new_session_path, alert: t(".invalid")
      return
    end

    @user = User.find_by(email_address: token_record.email)
    if @user
      token_record.consume!
      start_new_session_for(@user)
      redirect_to root_path, notice: t(".signed_in")
    else
      @token = params[:token]
      @email = token_record.email
      @user = User.new(email_address: token_record.email)
      render :new_registration
    end
  end

  def create
    token_record = MagicLinkToken.find_valid(params[:token])
    unless token_record
      redirect_to new_session_path, alert: t(".invalid")
      return
    end

    @user = User.new(
      email_address: token_record.email,
      first_name: params[:user][:first_name],
      last_name: params[:user][:last_name]
    )

    if @user.save
      @user.authentications.create!(
        provider: "email",
        uid: @user.email_address,
        verified_at: Time.current
      )
      token_record.consume!
      start_new_session_for(@user)
      redirect_to root_path, notice: t(".registered")
    else
      @token = params[:token]
      @email = token_record.email
      render :new_registration, status: :unprocessable_entity
    end
  end
end
