class MagicLinkCallbacksController < ApplicationController
  include Signupable

  allow_unauthenticated_access

  def show
    token_record = MagicLinkToken.find_valid(params[:token])
    unless token_record
      redirect_to(authenticated? ? root_path : new_session_path, alert: t(".invalid"))
      return
    end

    @user = User.find_by(email_address: token_record.email)
    if @user
      # Atomic consume prevents double-spend from concurrent requests
      consumed = MagicLinkToken.consume!(token_record.token)
      unless consumed
        redirect_to(authenticated? ? root_path : new_session_path, alert: t(".invalid"))
        return
      end
      start_new_session_for(@user)
      redirect_to magic_link_return_path(token_record), notice: t(".signed_in")
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
      redirect_to(authenticated? ? root_path : new_session_path, alert: t(".invalid"))
      return
    end

    unless signups_open?
      redirect_to new_session_path,
                  alert: t("registrations.closed.oauth_blocked"),
                  status: :see_other
      return
    end

    @user = User.new(
      email_address: token_record.email,
      first_name: params[:user][:first_name],
      last_name: params[:user][:last_name]
    )

    token_consumed = false

    success = commit_signup_atomically(@user) do |user|
      # Atomic compare-and-swap: if a concurrent request already consumed the
      # token, raise Rollback to unwind user creation — no orphaned User row.
      token_consumed = MagicLinkToken.consume!(token_record.token)
      raise ActiveRecord::Rollback unless token_consumed

      user.authentications.create!(
        provider: "email",
        uid: user.email_address,
        verified_at: Time.current
      )
    end

    if success && token_consumed
      start_new_session_for(@user)
      redirect_to after_authentication_url, notice: t(".registered")
    elsif @user.errors.any?
      # User failed model validation — re-render the registration form.
      @token = params[:token]
      @email = token_record.email
      render :new_registration, status: :unprocessable_entity
    else
      # Token was consumed by a concurrent request — treat as invalid.
      redirect_to(authenticated? ? root_path : new_session_path, alert: t(".invalid"))
    end
  end

  private

  # Server-side intent → fixed path. Never trust a user-supplied URL here.
  def magic_link_return_path(token_record)
    case token_record.intent
    when "set_password" then edit_settings_password_path
    else after_authentication_url
    end
  end
end
