# The deferred workspace claims (invitation + open-link join) parked while a
# signup or OAuth link waits on proof of email ownership. This is the single
# home of the claim exception matrix, previously duplicated — and drifting —
# between Signupable and Settings::ConnectedAccountsController#verify.
#
# Two claim modes, because the two claim moments intentionally differ:
#
# * #claim! — signup-time (session-parked tokens). Abort semantics: a stale
#   invitation (Invitation::NotAcceptable) or full workspace
#   (Workspace::AtCapacity) PROPAGATES so the caller's transaction rolls the
#   whole signup back. An unmatched invitation token stays unspent (parked for
#   the signup gate), and a still-valid join token is left parked for a
#   pre-existing user (drive-by-join re-consent guard).
# * #claim — verification-time (tokens parked on an Authentication). Continue
#   semantics: the user proved email ownership and nothing here may block
#   sign-in, so every failure becomes an entry in #problems for the caller to
#   render. The claim is one-shot (verification links are single-use), so any
#   present token is spent by the attempt.
#
# Callers own token storage and message rendering: #spent says which tokens to
# drop (session keys / Authentication columns — those writes aren't
# transactional, so spends survive a DB rollback by design), and #problems
# holds symbols each site maps to its own contextual i18n copy.
class PendingClaims
  attr_reader :problems, :spent

  def initialize(invitation_token: nil, join_token: nil, join_digest: nil)
    @invitation_token = invitation_token
    @join_token = join_token
    @join_digest = join_digest
    @problems = []
    @spent = []
  end

  def claim!(user, newly_registered: true)
    claim_invitation(user, one_shot: false, abort_on_stale: true)
    claim_join(user, newly_registered: newly_registered, abort_on_capacity: true)
    self
  end

  def claim(user)
    claim_invitation(user, one_shot: true, abort_on_stale: false)
    claim_join(user, newly_registered: true, abort_on_capacity: false)
    self
  end

  private

  def claim_invitation(user, one_shot:, abort_on_stale:)
    return if @invitation_token.blank?

    spend(:invitation) if one_shot
    consumed = Invitation.consume!(
      token: @invitation_token, user: user, expected_email: user.email_address
    )
    spend(:invitation) if consumed
  rescue Invitation::EmailMismatch
    # Addressed to a different email than the one proven here. Skip it rather
    # than aborting an otherwise legitimate claim; the token can never be
    # claimed by this user, so it is spent in both modes.
    spend(:invitation)
    @problems << :invitation_email_mismatch
  rescue Invitation::NotAcceptable
    # Stale (consumed/expired/non-admittable). The token is spent either way —
    # a retry would hit the same dead invitation and reject forever. The
    # invitation row itself stays reclaimable via a fresh emailed link.
    spend(:invitation)
    raise if abort_on_stale
    @problems << :invitation_consumed
  end

  def claim_join(user, newly_registered:, abort_on_capacity:)
    return if @join_token.blank? && @join_digest.blank?

    link = find_join_link

    # A brand-new account's signup is its own consent to join the link it
    # followed. A pre-existing user may be authenticating for an unrelated
    # reason with a lured-in token riding the session — never silently
    # force-join them. A still-valid token stays parked so the pending-join
    # banner can offer an explicit Join / Dismiss; anything stale spends below.
    return if !newly_registered && link&.workspace&.accepting_open_joins?

    begin
      # A stale link is a silent no-op inside WorkspaceJoinLink#admit.
      link&.admit(user)
    rescue Workspace::AlreadyMember
      # Benign: already in the workspace.
    rescue Workspace::AtCapacity
      raise if abort_on_capacity
      @problems << :join_link_at_capacity
    ensure
      # One-shot: once admission is attempted the token is spent regardless of
      # outcome — a terminal failure like capacity must not resurrect it.
      spend(:join)
    end
  end

  def find_join_link
    if @join_token.present?
      WorkspaceJoinLink.find_active(@join_token)
    else
      WorkspaceJoinLink.find_active_by_digest(@join_digest)
    end
  end

  def spend(kind)
    @spent << kind unless @spent.include?(kind)
  end
end
