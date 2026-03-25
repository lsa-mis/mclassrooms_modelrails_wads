class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :authentications, dependent: :destroy
  has_one :preferences, class_name: "UserPreferences", dependent: :destroy
  has_one_attached :avatar
  has_many :memberships, dependent: :destroy
  has_many :workspaces, through: :memberships
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :invited_by_id, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :first_name, presence: true, length: { maximum: 100 }
  validates :last_name, presence: true, length: { maximum: 100 }
  validates :password, length: { minimum: 12 }, if: -> { password_digest_changed? || new_record? }
  validate :password_not_pwned, if: -> { password_digest_changed? || new_record? }

  MAX_FAILED_ATTEMPTS = 5
  LOCK_DURATION = 1.hour

  def full_name
    "#{first_name} #{last_name}"
  end

  def locked?
    return false if locked_at.nil?
    locked_at > LOCK_DURATION.ago
  end

  def register_failed_login!
    increment!(:failed_login_attempts)
    update!(locked_at: Time.current) if failed_login_attempts >= MAX_FAILED_ATTEMPTS
  end

  def register_successful_login!
    update!(failed_login_attempts: 0, locked_at: nil)
  end

  private

  def password_not_pwned
    return if password.blank?
    if Pwned::Password.new(password).pwned?
      errors.add(:password, :pwned)
    end
  rescue Pwned::Error
    # Network error — allow password (don't block registration on external service failure)
  end
end
