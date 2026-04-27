class Authentication < ApplicationRecord
  belongs_to :user

  enum :provider, { email: "email", google: "google", github: "github" }

  PROVIDER_DISPLAY_NAMES = {
    "email"  => "Email",
    "google" => "Google",
    "github" => "GitHub"
  }.freeze

  def self.display_name_for(provider_string)
    PROVIDER_DISPLAY_NAMES.fetch(provider_string, provider_string.to_s.titleize)
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

  def token_expired?
    verification_sent_at.present? && verification_sent_at < TOKEN_LIFETIME.ago
  end

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

  def generate_verification_token!
    assign_verification_token
    save!
  end

  def verify!
    update!(
      verified_at: Time.current,
      verification_token: nil,
      verification_sent_at: nil
    )
  end
end
