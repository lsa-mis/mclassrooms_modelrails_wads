class Authentication < ApplicationRecord
  belongs_to :user

  enum :provider, { email: "email", google: "google", github: "github" }

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

  scope :verified, -> { where.not(verified_at: nil) }
  scope :pending,  -> { where(verified_at: nil).where.not(verification_token: nil) }
  scope :oauth,    -> { where.not(provider: "email") }

  def verified?
    verified_at.present?
  end

  def pending?
    verified_at.nil? && verification_token.present?
  end

  # True iff (a) this auth is verified AND (b) it's the only verified auth for the user.
  # Used by the destroy guard to prevent removing the user's last verified sign-in method.
  def only_verified_remaining?
    verified? && user.authentications.verified.count <= 1
  end

  # Returns true only if a token was sent AND is now stale. False when no token was sent.
  # Used by the OAuth verification flow where the token must already exist (find_by(token:)).
  def token_expired?
    verification_sent_at.present? && verification_sent_at < TOKEN_LIFETIME.ago
  end

  # Returns true if no token was ever sent OR the sent token is now stale.
  # Pessimistic-nil semantics — used by registration email verification where "no token" means "expired".
  def verification_token_expired?
    verification_sent_at.nil? || token_expired?
  end

  def assign_verification_token
    assign_attributes(
      verification_token: SecureRandom.urlsafe_base64(32),
      verification_sent_at: Time.current,
      verified_at: nil
    )
  end

  # Defensive retry budget for the astronomically-unlikely case where
  # SecureRandom.urlsafe_base64(32) collides with an existing verification_token
  # (256 bits of entropy → ~2^-256 per attempt). The unique index on
  # verification_token would surface a collision as ActiveRecord::RecordNotUnique;
  # we regenerate and retry rather than 500 the user.
  TOKEN_GENERATION_MAX_ATTEMPTS = 3

  def generate_verification_token!
    attempts = 0
    begin
      assign_verification_token
      save!
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      retry if attempts < TOKEN_GENERATION_MAX_ATTEMPTS
      raise
    end
  end

  def verify!
    update!(
      verified_at: Time.current,
      verification_token: nil,
      verification_sent_at: nil
    )
  end

  private

  def broadcast_target
    [ user, :authentications ]
  end
end
