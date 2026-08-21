class Authentication < ApplicationRecord
  belongs_to :user

  enum :provider, { email: "email", google: "google", github: "github", okta: "okta" }

  include Broadcastable

  def self.broadcast_events
    [ :create, :update, :destroy ]
  end

  def self.display_name_for(provider_string)
    I18n.t("authentication.providers.#{provider_string}",
           default: provider_string.to_s.titleize)
  end

  def display_provider
    self.class.display_name_for(provider)
  end

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

  def verify!
    update!(verified_at: Time.current)
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
