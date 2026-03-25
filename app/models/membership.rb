class Membership < ApplicationRecord
  include Discardable

  belongs_to :user
  belongs_to :workspace
  belongs_to :role

  validates :user_id, uniqueness: { scope: :workspace_id }
end
