module Signupable
  extend ActiveSupport::Concern

  # Runs user creation, invitation acceptance, and open-link join in ONE
  # transaction; true on commit, false on every handled failure. Sets
  # flash.now[:alert] only on Invitation::NotAcceptable — callers rely on
  # @user.errors otherwise. Full exception matrix: /docs/developer/application-flows.
  #
  # The invitation/join exception matrix itself lives in PendingClaims (shared
  # with the verification-time claim, Authentication#claim_pending!). What is
  # deliberately signup-specific here — do not "unify" it away:
  # * abort semantics: a stale invitation or full workspace rolls the whole
  #   signup back (PendingClaims#claim! propagates), where the verify-time
  #   claim must never block sign-in;
  # * session-token bookkeeping: spent tokens are dropped from the session even
  #   when the DB rolled back — session writes aren't transactional, and
  #   re-parking a dead token would reject forever. The invitation itself stays
  #   pending? (accept! guards before marking it consumed), so it's still
  #   reclaimable via the emailed link;
  # * copy: the mismatch message speaks to a signup, not a verification
  #   (contextually different wording from the verify site by design).
  def commit_signup_atomically(user, newly_registered: true)
    claims = PendingClaims.new(
      invitation_token: session[:pending_invitation_token],
      join_token: session[:pending_join_token]
    )
    ApplicationRecord.transaction do
      user.save!
      yield(user)
      claims.claim!(user, newly_registered: newly_registered)
    end
    settle_pending_claims(claims)
    true
  rescue Invitation::NotAcceptable
    settle_pending_claims(claims)
    flash.now[:alert] = I18n.t("registrations.create.invitation_consumed")
    false
  rescue ActiveRecord::RecordInvalid, Workspace::NotAdmittableError,
         Workspace::AlreadyMember, Workspace::AtCapacity
    settle_pending_claims(claims)
    false
  end

  private

  # Drops spent tokens and renders the one continue-past problem (mismatch)
  # with a persistent flash — these callers redirect, so flash.now wouldn't
  # survive to the landing page.
  def settle_pending_claims(claims)
    session.delete(:pending_invitation_token) if claims.spent.include?(:invitation)
    session.delete(:pending_join_token) if claims.spent.include?(:join)
    return unless claims.problems.include?(:invitation_email_mismatch)

    flash[:alert] = I18n.t("registrations.create.invitation_email_mismatch")
  end
end
