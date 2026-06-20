# An external client's scoped access to a single project (Clientside). A client
# is a regular User; this row is the EXTERNAL relationship — deliberately NOT a
# Membership, so clients never enter workspace policies or member-seat counting.
class ClientAccess < ApplicationRecord
  include Discardable

  belongs_to :project
  belongs_to :user

  validates :company_name, presence: true
  validates :user_id, uniqueness: { scope: :project_id }
  validate :project_clientside_enabled, on: :create

  private

  def project_clientside_enabled
    return if project&.clientside_enabled?
    errors.add(:base, :clientside_disabled)
  end
end
