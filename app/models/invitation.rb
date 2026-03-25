class Invitation < ApplicationRecord
  belongs_to :invitable, polymorphic: true
  belongs_to :role
  belongs_to :invited_by, class_name: "User"
  belongs_to :accepted_by, class_name: "User", optional: true

  enum :status, { pending: "pending", accepted: "accepted", declined: "declined", revoked: "revoked" }, default: "pending"

  validates :role, presence: true
  validates :invited_by, presence: true
  validates :expires_at, presence: true

  before_create :generate_token

  scope :pending, -> { where(status: "pending").where("expires_at > ?", Time.current) }
  scope :expired, -> { where(status: "pending").where("expires_at <= ?", Time.current) }

  def accept!(user)
    raise ActiveRecord::RecordInvalid.new(self), "User is already a member" if invitable.memberships.kept.exists?(user: user)

    transaction do
      update!(
        status: "accepted",
        accepted_by: user,
        accepted_at: Time.current
      )
      invitable.memberships.create!(
        user: user,
        role: role
      )
    end
  end

  def decline!
    update!(status: "declined", declined_at: Time.current)
  end

  def revoke!
    update!(status: "revoked", revoked_at: Time.current)
  end

  def resend!
    update!(
      token: SecureRandom.urlsafe_base64(32),
      expires_at: 7.days.from_now
    )
  end

  def expired?
    expires_at <= Time.current
  end

  def magic_link?
    email.nil?
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end
end
