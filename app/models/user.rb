class User < ApplicationRecord
  has_secure_password validations: false
  attr_accessor :current_password

  has_many :sessions, dependent: :destroy
  has_many :authentications, dependent: :destroy
  has_one :preferences, class_name: "UserPreferences", dependent: :destroy
  has_one_attached :avatar
  has_one_attached :avatar_original
  has_many :memberships, dependent: :destroy
  has_many :workspaces, through: :memberships
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :invited_by_id, dependent: :nullify
  has_many :project_memberships, dependent: :destroy
  has_many :projects, through: :project_memberships

  after_create :create_personal_workspace
  after_create :check_gravatar_later
  after_update_commit :check_gravatar_later, if: :saved_change_to_email_address?

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :pending_email, with: ->(e) { e&.strip&.downcase }

  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  validates :email_address, presence: true, uniqueness: true,
                            format: { with: EMAIL_FORMAT }
  validates :first_name, presence: true, length: { maximum: 100 }
  validates :last_name, presence: true, length: { maximum: 100 }
  validates :password, length: { minimum: 12 }, if: -> { password.present? && (password_digest_changed? || new_record?) }
  validates :password, confirmation: true, if: -> { password.present? }
  validate :password_not_pwned, if: -> { password.present? && (password_digest_changed? || new_record?) }

  validates :pending_email, format: { with: EMAIL_FORMAT }, allow_blank: true
  validate :pending_email_not_taken, if: -> { pending_email.present? }
  validates :avatar_source, inclusion: { in: %w[upload gravatar initials] }
  validates :avatar,
    content_type: %w[image/png image/jpeg image/gif image/webp],
    size: { less_than: 5.megabytes }
  validates :avatar_original,
    content_type: %w[image/png image/jpeg image/gif image/webp],
    size: { less_than: 10.megabytes }
  validates :primary_color, inclusion: { in: 0..360 }, allow_nil: true

  MAX_FAILED_ATTEMPTS = 5
  LOCK_DURATION = 1.hour

  def full_name
    "#{first_name} #{last_name}"
  end

  def initials
    parts = [ first_name, last_name ].map(&:to_s).reject(&:blank?)
    return "?" if parts.empty?
    parts.map { |p| p[0].upcase }.join
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

  def has_password?
    password_digest.present?
  end

  def gravatar_url(size: 128)
    return nil if email_address.blank?

    hash = Digest::SHA256.hexdigest(email_address.strip.downcase)
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=404"
  end

  def available_avatar_sources
    sources = %w[upload initials]
    sources << "gravatar" if has_gravatar?
    sources
  end

  def initiate_email_change!(new_email, password)
    return false unless has_password?
    return false unless authenticate(password)

    normalized = new_email.strip.downcase
    return false if normalized == email_address

    self.pending_email = new_email
    self.pending_email_token = SecureRandom.urlsafe_base64(32)
    self.pending_email_sent_at = Time.current

    save
  end

  def confirm_email_change!(token)
    return false if token.blank?
    return false if pending_email_token != token
    return false unless pending_email_token_valid?

    transaction do
      self.email_address = pending_email
      clear_pending_email_fields
      save!

      authentications.email.update_all(uid: email_address)
    end

    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def cancel_email_change!
    clear_pending_email_fields
    save!
  end

  def pending_email_token_valid?
    pending_email_token.present? &&
      pending_email_sent_at.present? &&
      pending_email_sent_at > 24.hours.ago
  end

  private

  def check_gravatar_later
    CheckGravatarJob.perform_later(self)
  end

  def create_personal_workspace
    workspace = Workspace.create!(name: "#{first_name}'s Workspace", personal: true)
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

  def pending_email_not_taken
    if User.where.not(id: id).exists?(email_address: pending_email)
      errors.add(:pending_email, :taken)
    end
  end

  def clear_pending_email_fields
    self.pending_email = nil
    self.pending_email_token = nil
    self.pending_email_sent_at = nil
  end
end
