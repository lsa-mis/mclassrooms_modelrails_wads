class User < ApplicationRecord
  has_secure_password validations: false
  has_many :sessions, dependent: :destroy
  has_many :authentications, dependent: :destroy
  has_one :preferences, class_name: "UserPreferences", dependent: :destroy
  has_one_attached :avatar
  has_many :memberships, dependent: :destroy
  has_many :workspaces, through: :memberships
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :invited_by_id, dependent: :nullify
  has_many :project_memberships, dependent: :destroy
  has_many :projects, through: :project_memberships

  after_create :create_personal_workspace

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :first_name, presence: true, length: { maximum: 100 }
  validates :last_name, presence: true, length: { maximum: 100 }
  validates :password, length: { minimum: 12 }, if: -> { password.present? && (password_digest_changed? || new_record?) }
  validates :password, confirmation: true, if: -> { password.present? }
  validate :password_not_pwned, if: -> { password.present? && (password_digest_changed? || new_record?) }

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

  def generate_magic_link_token!
    update!(
      magic_link_token: SecureRandom.urlsafe_base64(32),
      magic_link_sent_at: Time.current
    )
  end

  def magic_link_token_valid?
    magic_link_token.present? && magic_link_sent_at.present? && magic_link_sent_at > 15.minutes.ago
  end

  def clear_magic_link_token!
    update!(magic_link_token: nil, magic_link_sent_at: nil)
  end

  def has_password?
    password_digest.present?
  end

  private

  def create_personal_workspace
    workspace = Workspace.create!(name: "#{first_name}'s Workspace")
    owner_role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
    workspace.memberships.create!(user: self, role: owner_role)
  end

  def password_not_pwned
    return if password.blank?
    if Pwned::Password.new(password).pwned?
      errors.add(:password, :pwned)
    end
  rescue Pwned::Error
    # Network error — allow password (don't block registration on external service failure)
  end
end
