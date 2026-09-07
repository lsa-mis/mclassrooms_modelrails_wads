class MagicLinkToken < ApplicationRecord
  include Consumable

  validates :token_digest, presence: true, uniqueness: true
  normalizes :email, with: ->(e) { EmailNormalizer.normalize(e) }
  # Encrypted at rest (#902): deterministic for the one-unconsumed-token-per-
  # address index that create_for_email's supersede relies on.
  encrypts :email, deterministic: true, downcase: true
  validates :email, presence: true, format: { with: User::EMAIL_FORMAT }
  validates :expires_at, presence: true

  # The bearer token is 256 bits of entropy, so it's stored only as a plain
  # SHA256 digest (no pepper needed — unlike the 6-digit ReauthenticationChallenge
  # code, there's no offline brute force against a 2^256 space). The plaintext
  # lives only in the outgoing email URL. One formula, so lookup and insert
  # can never disagree.
  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  # Atomically issues a magic link token for the given email. Supersedes any
  # prior unconsumed token (expired or active) so at most one is valid at a
  # time. The partial unique index on (email) WHERE consumed_at IS NULL makes
  # the supersede race-safe across connections: if two threads both pass the
  # supersede UPDATE, only one INSERT wins. Returns the plaintext token to
  # email, or nil for the losing thread — the winner already emailed the one
  # valid link, and the plaintext is unrecoverable from the digest.
  def self.create_for_email(email, intent: nil)
    token = SecureRandom.urlsafe_base64(32)

    transaction do
      where(email: email, consumed_at: nil).update_all(consumed_at: Time.current)
      create!(token_digest: digest(token), email: email, expires_at: 15.minutes.from_now, intent: intent)
    end
    token
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def self.find_valid(token)
    find_by(token_digest: digest(token))
      &.then { |record| record.expires_at > Time.current && record.consumed_at.nil? ? record : nil }
  end

  # Atomic single-use consume (see Consumable#consume_matching). Returns the
  # now-consumed record, or nil if it was already spent or expired.
  def self.consume!(token)
    token_digest = digest(token)
    return nil unless consume_matching(token_digest: token_digest).positive?
    find_by(token_digest: token_digest)
  end

  def consume!
    rows_updated = self.class.where(id: id, consumed_at: nil).update_all(consumed_at: Time.current)
    if rows_updated > 0
      reload
      true
    else
      false
    end
  end
end
