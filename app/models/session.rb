class Session < ApplicationRecord
  belongs_to :user

  validates :ip_address, length: { maximum: 45 }, allow_nil: true
  validates :user_agent, length: { maximum: 512 }, allow_nil: true
end
