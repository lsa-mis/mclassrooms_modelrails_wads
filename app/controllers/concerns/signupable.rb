module Signupable
  extend ActiveSupport::Concern

  # Runs user creation and invitation acceptance in a single transaction.
  # The block receives the saved user and should perform any in-transaction
  # work (creating authentications, generating verification tokens, etc.).
  # Exceptions other than Invitation::NotAcceptable and ActiveRecord::RecordInvalid
  # will propagate beyond this method.
  #
  # Returns true on commit, false on validation failure or invitation race.
  # Sets flash.now[:alert] only on Invitation::NotAcceptable (so the caller
  # can rely on @user.errors for model-validation failures).
  def commit_signup_atomically(user, &block)
    ApplicationRecord.transaction do
      user.save!
      yield(user)
      accept_pending_invitation!(user)
    end
    true
  rescue Invitation::NotAcceptable
    flash.now[:alert] = I18n.t("registrations.create.invitation_consumed")
    false
  rescue ActiveRecord::RecordInvalid
    false
  end

  # Consumes the session's pending invitation token. Idempotent if no token
  # is present. Raises Invitation::NotAcceptable if the invitation is no
  # longer acceptable. Session token is deleted ONLY on successful acceptance.
  def accept_pending_invitation!(user)
    consumed = Invitation.consume!(
      token: session[:pending_invitation_token],
      user: user,
      expected_email: user.email_address
    )
    session.delete(:pending_invitation_token) if consumed
  rescue Invitation::EmailMismatch
    # The invitation was addressed to a different email than the one being
    # registered here. Skip it rather than aborting an otherwise legitimate
    # signup, drop the token so it isn't retried, and tell the user why they
    # weren't added to the invited workspace. (These callers redirect, so a
    # persistent flash — not flash.now — survives to the landing page.)
    session.delete(:pending_invitation_token)
    flash[:alert] = I18n.t("registrations.create.invitation_email_mismatch")
  end
end
