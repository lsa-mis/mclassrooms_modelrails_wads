class WebauthnChallenge < ApplicationRecord
  include Consumable

  belongs_to :user, optional: true
  validates :challenge, presence: true, uniqueness: true
  validates :purpose, inclusion: { in: %w[registration authentication reauthentication] }

  def self.store(challenge:, purpose:, user: nil)
    create!(challenge: challenge, purpose: purpose, user: user, expires_at: 5.minutes.from_now)
  end

  # Atomic single-use consume (see Consumable#consume_matching), additionally
  # scoped by purpose so an authentication challenge can't be spent as a
  # registration one. Returns the now-consumed record, or nil.
  def self.consume!(challenge, purpose:)
    return nil unless consume_matching(challenge: challenge, purpose: purpose).positive?
    find_by(challenge: challenge)
  end
end
