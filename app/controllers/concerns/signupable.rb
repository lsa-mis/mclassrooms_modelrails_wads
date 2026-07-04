module Signupable
  extend ActiveSupport::Concern

  # Runs user creation, invitation acceptance, and open-link join in a single
  # transaction. The block receives the saved user and should perform any
  # in-transaction work (creating authentications, generating verification
  # tokens, etc.). Exceptions other than Invitation::NotAcceptable,
  # ActiveRecord::RecordInvalid, and Workspace::NotAdmittableError will
  # propagate beyond this method.
  #
  # Returns true on commit, false on validation failure, invitation race, or a
  # parked open-link join whose workspace goes non-admittable under admit's lock
  # — the TOCTOU backstop for a workspace archived/suspended/deleted between
  # accept_pending_join_link!'s pre-check and admit's locked re-check
  # (Workspace#admit raises NotAdmittableError). Rescued the same as RecordInvalid
  # so the whole signup rolls back cleanly with no orphaned user, instead of the
  # error escaping and aborting registration with a raw exception. Normal
  # stale-workspace parked joins never reach here — the pre-check drops them.
  # Sets flash.now[:alert] only on Invitation::NotAcceptable (so the caller
  # can rely on @user.errors for model-validation failures).
  def commit_signup_atomically(user, &block)
    ApplicationRecord.transaction do
      user.save!
      yield(user)
      accept_pending_invitation!(user)
      accept_pending_join_link!(user)
    end
    true
  rescue Invitation::NotAcceptable
    # Clear the parked token here — session writes aren't transactional, so
    # this persists even though the DB rolls back. Without it, a retry would
    # hit the same non-admittable workspace and reject forever. The
    # invitation itself stays pending? (accept! guards before marking it
    # consumed), so it's still reclaimable via the emailed link.
    session.delete(:pending_invitation_token)
    flash.now[:alert] = I18n.t("registrations.create.invitation_consumed")
    false
  rescue ActiveRecord::RecordInvalid, Workspace::NotAdmittableError
    false
  end

  # Consumes the session's pending invitation token. Idempotent if no token
  # is present. Raises Invitation::NotAcceptable if the invitation is no longer
  # acceptable — the caller's commit_signup_atomically rescue clears the token
  # in that case (I1), so a retry can't loop. This method itself deletes the
  # token only on successful acceptance or an EmailMismatch skip.
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

  # Consumes the session's pending open-link join token for a freshly-signed-up,
  # email-verified user. Stale link conditions (revoked, policy reverted,
  # workspace archived/suspended/deleted) are silent no-ops — a visitor who
  # was never a member must not learn the workspace is locked. Benign
  # "already a member" is rescued; other capacity errors propagate — the
  # outer commit_signup_atomically rescues RecordInvalid and returns false,
  # consistent with the invitation path.
  def accept_pending_join_link!(user)
    token = session[:pending_join_token]
    return if token.blank?

    link = WorkspaceJoinLink.active.find_by(token: token)
    if link.nil? || !link.workspace.open_join? || !link.workspace.admittable?
      session.delete(:pending_join_token)
      return
    end

    begin
      link.workspace.admit(user, role: link.workspace.default_self_join_role)
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.message.match?(/already a member/i)
    ensure
      session.delete(:pending_join_token)
    end
  end
end
