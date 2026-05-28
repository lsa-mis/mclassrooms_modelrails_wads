class WorkspaceJoinLink < ApplicationRecord
  # Stored, revocable token (vs. the signed-stateless generates_token_for used
  # for email verification). Revocability is the requirement that picks this
  # primitive — `regenerate_token` gives us atomic rotation for free, and
  # `revoked_at` makes individual links killable.
  has_secure_token :token

  belongs_to :workspace
  belongs_to :created_by, class_name: "User"

  scope :active, -> { where(revoked_at: nil) }

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
