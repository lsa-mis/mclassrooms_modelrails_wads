class Authentication < ApplicationRecord
  belongs_to :user

  enum :provider, { email: "email", google: "google", github: "github", okta: "okta" }

  include Broadcastable

  def self.broadcast_events
    [ :create, :update, :destroy ]
  end

  # Dynamic key, no fallback: spec/code_smells/dynamic_i18n_keys_have_values_spec.rb
  # proves every configured provider has its label.
  def self.display_name_for(provider_string)
    I18n.t("authentication.providers.#{provider_string}")
  end

  def display_provider
    self.class.display_name_for(provider)
  end

  normalizes :email, with: ->(e) { EmailNormalizer.normalize(e) }
  # Encrypted at rest (#902). uid is deterministic because (provider, uid) is
  # the sign-in lookup and a unique index — and for email-provider rows it is
  # the address itself (#903). No downcase: provider ids are opaque.
  encrypts :email
  encrypts :uid, deterministic: true
  # Parked invitation token: the same bearer credential as invitations.token,
  # kept until email verification claims it (#953). Non-deterministic: the
  # only index here is `WHERE … IS NOT NULL`, and nothing looks the column up
  # by value (fix round 1) — determinism would only make it byte-identical to
  # invitations.token for the same token, letting a leaked dump join a parked
  # signup to its invitation.
  encrypts :pending_invitation_token

  validates :provider, presence: true
  validates :uid, presence: true
  validates :provider, uniqueness: { scope: :user_id }
  validates :uid, uniqueness: { scope: :provider }
  validates :avatar_url, format: { with: /\Ahttps:\/\/\S+\z/i }, allow_blank: true

  TOKEN_LIFETIME = 24.hours

  # Stateless, signed email-verification token (Rails generates_token_for).
  # Nothing is stored: the token carries the record id and a payload, and
  # find_by_token_for re-derives it. Embedding verified_at makes the link
  # single-use — once the auth is verified the payload changes, so any
  # previously-issued link stops validating. Expiry is enforced by the token
  # itself (no verification_sent_at bookkeeping, no collision retries).
  generates_token_for :email_verification, expires_in: TOKEN_LIFETIME do
    verified_at
  end

  scope :verified, -> { where.not(verified_at: nil) }
  scope :pending,  -> { where(verified_at: nil) }
  scope :oauth,    -> { where.not(provider: "email") }

  def verified?
    verified_at.present?
  end

  # An auth is pending until it's verified. Every unverified auth is created
  # with a verification email on its way (token minted on demand), so
  # "not verified" is exactly "awaiting verification".
  def pending?
    verified_at.nil?
  end

  # True iff (a) this auth is verified AND (b) it's the only verified auth for the user.
  # Used by the destroy guard to prevent removing the user's last verified sign-in method.
  def only_verified_remaining?
    verified? && user.authentications.verified.count <= 1
  end

  # Compare-and-swap, the MagicLinkToken#consume! shape (#950): the token payload
  # already dies once verified_at is set, but two requests inside the same
  # window both pass find_by_token_for; the WHERE is what makes the second lose.
  # update_all fires no callbacks, so the Broadcastable update is sent by hand.
  def verify!
    now = Time.current
    return false unless self.class.where(id: id, verified_at: nil).update_all(verified_at: now, updated_at: now) == 1

    reload
    broadcast_changes
    true
  end

  # One-shot claim of everything parked on this Authentication during the
  # deferred (unverified-email OAuth) signup flow: invitation token + join-link
  # digest. Runs at email-verification time with continue semantics — the user
  # just proved ownership, so no stale claim may block sign-in; failures come
  # back as `problems` for the caller to render. The exception matrix lives in
  # PendingClaims (shared with the signup-time claim in Signupable).
  # See /docs/developer/application-flows (Deferred claims on the unverified-OAuth path).
  #
  # Every attempted token is spent (verify never retries): spent columns are
  # cleared even when the claim failed or raised, so no token lingers as
  # orphaned state. The clear is a separate write from the claim transaction —
  # a process crash in between re-runs nothing (the verification link is
  # single-use), it only leaves the already-spent token to this same cleanup.
  def claim_pending!(user)
    claims = PendingClaims.new(
      invitation_token: pending_invitation_token,
      join_digest: pending_join_link_digest
    )
    begin
      claims.claim(user)
    ensure
      cleared = {}
      cleared[:pending_invitation_token] = nil if claims.spent.include?(:invitation)
      cleared[:pending_join_link_digest] = nil if claims.spent.include?(:join)
      update!(**cleared) if cleared.any?
    end
    claims
  end

  private

  def broadcast_target
    [ user, :authentications ]
  end
end
