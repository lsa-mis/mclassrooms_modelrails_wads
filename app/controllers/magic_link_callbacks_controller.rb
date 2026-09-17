class MagicLinkCallbacksController < ApplicationController
  include Signupable
  include MagicLinkReplayable

  allow_unauthenticated_access

  # GET only. Never consumes the token or starts a session — a mail scanner or
  # prefetcher doing a bare GET must not be able to burn a link or sign anyone
  # in. Existing users get a confirmation page whose button POSTs to the nested
  # session (MagicLinkCallbacks::SessionsController#create); new users get the
  # registration form (which already POSTs to #create).
  def show
    @token_record = MagicLinkToken.find_valid(params[:token])
    unless @token_record
      # A spent link re-presented by its signed-in owner is not a failure. The
      # existing "already signed in" answer and its home-path destination are
      # reused rather than minted, and deliberately NOT routed through the
      # token's intent: a superseded set_password link clicked from an old
      # email must not bounce a signed-in user to the password page.
      if replayed_by_owner(params[:token])
        redirect_to authenticated_home_path, notice: t("authentication.already_signed_in")
      else
        redirect_to(authenticated? ? root_path : new_session_path, alert: t(".invalid"))
      end
      return
    end

    @token = params[:token]
    @email = @token_record.email
    @user = User.find_by(email_address: @token_record.email)
    if @user
      render :confirm
    else
      @user = User.new(email_address: @token_record.email)
      render :new_registration
    end
  end

  def create
    token_record = MagicLinkToken.find_valid(params[:token])
    unless token_record
      # A double-submitted registration form: the first POST consumed the
      # token and signed the user in, and this one arrived from that same
      # browser. It answers what the first POST answered — the welcome — not
      # an expiry alert. (The "consumed by a concurrent request" branch below
      # gets no replay: an in-flight loser was dispatched before the winner's
      # cookie existed, so it is never authenticated and a branch there would
      # be dead code.)
      if replayed_by_owner(params[:token])
        redirect_to after_authentication_url, notice: t(".registered")
      else
        redirect_to(authenticated? ? root_path : new_session_path, alert: t(".invalid"))
      end
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
      token_consumed = MagicLinkToken.consume!(params[:token])
      raise ActiveRecord::Rollback unless token_consumed

      user.authentications.create!(
        provider: "email",
        verified_at: Time.current
      )
    end

    if success && token_consumed
      start_new_session_for(@user)
      # Here, not inside commit_signup_atomically: a concurrently-consumed
      # token rolls the signup back yet still returns true, and never from a
      # User callback (see WelcomeNotifier).
      WelcomeNotifier.with(record: @user).deliver(nil)
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
end
