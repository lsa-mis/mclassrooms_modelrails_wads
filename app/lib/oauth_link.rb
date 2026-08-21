# The OAuth linking decision: given a provider callback (OmniAuth auth hash)
# and the current actor, decide what this identity may claim — an existing
# session, a link to the signed-in account, or a signup — and perform it.
# Extracted from OmniauthCallbacksController so the highest-consequence
# branching in the app is unit-testable without a full OAuth request cycle.
#
# #claim returns one Outcome from the CODES set below. The controller maps
# outcomes to HTTP (redirect + flash + session bookkeeping); this object owns
# the policy decisions plus their non-HTTP consequences (persistence, the
# throttled security/verification mailers).
#
# Error posture: only ActiveRecord::RecordInvalid / RecordNotUnique become a
# :failed outcome, and only around this flow's own writes — every write here
# persists provider-controlled data, so validation failures and uniqueness
# races are legitimate runtime conditions, not bugs. Anything else (e.g. the
# ArgumentError a provider/enum typo raises) propagates loudly instead of
# soft-failing as "linking failed" (previously a blanket controller rescue
# swallowed it).
class OauthLink
  CODES = %i[
    signed_in linked verification_sent verification_resent pending_in_progress
    already_linked collision signups_closed unverified_pending failed
  ].freeze

  Outcome = Data.define(:code, :user, :auth, :email, :provider_name, :problems, :spent_tokens)

  def initialize(auth_hash, actor: nil, signups_open: false, invitation_token: nil, join_token: nil)
    @identity = OauthIdentity.new(auth_hash)
    @actor = actor
    @signups_open = signups_open
    @invitation_token = invitation_token
    @join_token = join_token
  end

  def claim
    existing = Authentication.find_by(provider: identity.provider, uid: identity.uid)

    if existing
      claim_existing(existing)
    elsif @actor
      claim_link(@actor)
    else
      claim_signup
    end
  end

  private

  attr_reader :identity

  def claim_existing(auth)
    if @actor.present? && @actor.id != auth.user_id
      # Cross-user collision: the OAuth provider+uid is already linked to a
      # different user. Notify the legitimate owner (defense-in-depth) so
      # they're aware someone tried to attach their identity elsewhere.
      alert_collision_owner(auth)
      outcome(:collision)
    elsif auth.pending?
      send_verification(auth)
      outcome(:verification_resent, email: auth.email)
    else
      auth.update!(identity.auth_attrs)
      outcome(:signed_in, user: auth.user)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    outcome(:failed)
  end

  def claim_link(user)
    existing = user.authentications.find_by(provider: identity.provider)
    return outcome(:already_linked) if existing&.verified?
    return outcome(:pending_in_progress, email: existing.email) if existing&.pending?
    return outcome(:failed) if identity.email.blank?

    auth = user.authentications.build(
      provider: identity.provider,
      uid: identity.uid,
      email: identity.email,
      **identity.auth_attrs
    )

    if EmailNormalizer.equivalent?(identity.email, user.email_address) && identity.email_verified?
      auth.verified_at = Time.current
      auth.save!
      outcome(:linked)
    else
      auth.save!
      send_verification(auth)
      outcome(:verification_sent, auth: auth, email: identity.email)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    outcome(:failed)
  end

  def claim_signup
    return outcome(:signups_closed) unless @signups_open

    if identity.email_verified?
      claim_verified_signup
    else
      claim_unverified_signup
    end
  end

  def claim_verified_signup
    claims = new_pending_claims
    existing = find_verified_user_by_email(identity.email)
    user = existing || create_user_from_identity

    # A pre-existing user linking a new verified provider must not be silently
    # force-joined by a pending join token riding the session (drive-by join) —
    # hence newly_registered below.
    ApplicationRecord.transaction do
      user.save!
      user.authentications.create!(
        provider: identity.provider,
        uid: identity.uid,
        email: identity.email,
        verified_at: Time.current,
        **identity.auth_attrs
      )
      claims.claim!(user, newly_registered: existing.nil?)
    end

    outcome(:signed_in, user: user, problems: claims.problems, spent_tokens: claims.spent)
  rescue Invitation::NotAcceptable, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique,
         Workspace::NotAdmittableError, Workspace::AlreadyMember, Workspace::AtCapacity
    # Spent session tokens still surface — session writes aren't transactional,
    # and re-parking a dead token would reject forever.
    outcome(:failed, spent_tokens: claims.spent)
  end

  def claim_unverified_signup
    # The provider explicitly reports the email as unverified. Refuse to
    # auto-link to an existing user (account-takeover risk) and refuse to
    # auto-verify. Create the user fresh — if the email already belongs to
    # another account, User validation raises and this becomes :failed.
    # Deferred claims: does NOT run PendingClaims — that would consume the
    # invitation before email ownership is proven. The tokens are parked on the
    # pending Authentication instead, claimed by Authentication#claim_pending!
    # once the verification link is clicked.
    auth = nil
    ApplicationRecord.transaction do
      user = create_user_from_identity
      auth = user.authentications.build(
        provider: identity.provider,
        uid: identity.uid,
        email: identity.email,
        pending_invitation_token: @invitation_token,
        pending_join_link_digest: parked_join_digest,
        **identity.auth_attrs
      )
      auth.save!
    end

    # deliver_later runs after the transaction commits (project convention:
    # deliver_later inside a transaction can enqueue a job that fires on rollback).
    send_verification(auth)
    outcome(:unverified_pending, email: identity.email, spent_tokens: %i[invitation join])
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    outcome(:failed)
  end

  def new_pending_claims
    PendingClaims.new(invitation_token: @invitation_token, join_token: @join_token)
  end

  # The join token is hashed at rest (WorkspaceJoinLink stores only a digest),
  # so park the digest — not the plaintext — for the deferred-OAuth claim.
  def parked_join_digest
    WorkspaceJoinLink.digest(@join_token) if @join_token.present?
  end

  def find_verified_user_by_email(email)
    user = User.find_by(email_address: email)
    return nil unless user
    return user if user.authentications.email.where.not(verified_at: nil).exists?
    nil
  end

  def create_user_from_identity
    User.create!(
      email_address: identity.email,
      first_name: identity.first_name,
      last_name: identity.last_name
    )
  end

  # Throttled to prevent flooding a victim if many attackers attempt this.
  def alert_collision_owner(auth)
    return unless EmailRecipientThrottle.allow!(auth.user.email_address, kind: :collision_alert)

    AuthenticationMailer.collision_alert(auth.user, identity.provider_name).deliver_later
  end

  def send_verification(auth)
    return unless EmailRecipientThrottle.allow!(auth.email, kind: :verification)

    AuthenticationMailer.link_verification_email(auth).deliver_later
  end

  def outcome(code, user: nil, auth: nil, email: nil, problems: [], spent_tokens: [])
    Outcome.new(
      code: code, user: user, auth: auth, email: email,
      provider_name: identity.provider_name, problems: problems, spent_tokens: spent_tokens
    )
  end
end
