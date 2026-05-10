class MagicLinkToken < ApplicationRecord
  validates :token, presence: true, uniqueness: true
  validates :email, presence: true, format: { with: User::EMAIL_FORMAT }
  validates :expires_at, presence: true

  # Atomically issues a magic link token for the given email. Supersedes any
  # prior unconsumed token (expired or active) so at most one is valid at a
  # time. The partial unique index on (email) WHERE consumed_at IS NULL makes
  # the supersede race-safe across connections: if two threads both pass the
  # supersede UPDATE, only one INSERT wins; the loser returns the winner's
  # token (rather than retrying with a fresh INSERT, which would invalidate
  # the email already in flight from the winner).
  def self.create_for_email(email)
    normalized_email = email.downcase
    token = SecureRandom.urlsafe_base64(32)

    transaction do
      where(email: normalized_email, consumed_at: nil).update_all(consumed_at: Time.current)
      create!(token: token, email: normalized_email, expires_at: 15.minutes.from_now)
    end
    token
  rescue ActiveRecord::RecordNotUnique
    where(email: normalized_email, consumed_at: nil).order(created_at: :desc).first&.token
  end

  def self.find_valid(token)
    find_by(token: token)
      &.then { |record| record.expires_at > Time.current && record.consumed_at.nil? ? record : nil }
  end

  # Atomic compare-and-swap: a single UPDATE with WHERE consumed_at IS NULL
  # so the database serializes concurrent consumers — only one observes
  # affected_rows == 1. SQLite's per-connection pessimistic lock would not
  # serialize across the Rails connection pool, so atomicity must live in
  # the WHERE clause, not the read-then-write.
  def self.consume!(token)
    rows_updated = where(token: token, consumed_at: nil)
                     .where("expires_at > ?", Time.current)
                     .update_all(consumed_at: Time.current)
    return nil unless rows_updated > 0
    find_by(token: token)
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
