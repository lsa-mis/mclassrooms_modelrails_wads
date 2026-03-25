class Authentication < ApplicationRecord
  belongs_to :user

  enum :provider, { email: "email", google: "google", github: "github" }

  validates :provider, presence: true
  validates :uid, presence: true
  validates :provider, uniqueness: { scope: :user_id }
  validates :uid, uniqueness: { scope: :provider }

  scope :verified, -> { where.not(verified_at: nil) }
  scope :oauth, -> { where.not(provider: "email") }

  def verified?
    verified_at.present?
  end

  def generate_verification_token!
    update!(
      verification_token: SecureRandom.urlsafe_base64(32),
      verification_sent_at: Time.current
    )
  end

  def verify!
    update!(
      verified_at: Time.current,
      verification_token: nil,
      verification_sent_at: nil
    )
  end

  def verification_token_expired?
    return true if verification_sent_at.nil?
    verification_sent_at < 24.hours.ago
  end
end
