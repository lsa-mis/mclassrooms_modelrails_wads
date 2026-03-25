class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :first_name, presence: true, length: { maximum: 100 }
  validates :last_name, presence: true, length: { maximum: 100 }
  validates :password, length: { minimum: 12 }, if: -> { password_digest_changed? || new_record? }
  validate :password_not_pwned, if: -> { password_digest_changed? || new_record? }

  def full_name
    "#{first_name} #{last_name}"
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
