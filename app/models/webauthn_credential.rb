# A registered passkey. Unlike Authentication (one row per OAuth/email provider),
# this is a *capability*: register once, authenticate many. A user may have many.
# verified_at is set once at registration and never cleared; to revoke, discard.
class WebauthnCredential < ApplicationRecord
  include Discardable

  belongs_to :user
  validates :external_id, presence: true, uniqueness: true
  validates :public_key, :sign_count, presence: true

  # Strict tier (notifications lifecycle arc): enrollment/removal are
  # credential mutations — the audit row commits with them or not at all.
  # Enrollment stays a callback: a duplicate create can't happen, the
  # external_id unique index sees to that. Removal can't — see discard! below.
  after_create :audit_added

  # Atomic advance with clone detection: a single UPDATE guarded by the current
  # count, so concurrent assertions can't both "advance" past the same value.
  # Per WebAuthn §7.2 the signature counter is only meaningful when nonzero —
  # platform passkeys (Apple/Google) always report 0, which means "no counter
  # support", not a clone. So accept when new_count is 0 OR strictly greater than
  # the stored count; flag a clone only on a nonzero, non-advancing count. MAX()
  # keeps the stored value monotonic so a stray 0 never lowers a real counter.
  def advance_sign_count!(new_count)
    rows = self.class.where(id: id)
             .where("? = 0 OR sign_count < ?", new_count, new_count)
             .update_all([ "sign_count = MAX(sign_count, ?), last_used_at = ?", new_count, Time.current ])
    raise Passkeys::ClonedAuthenticator, "sign_count regressed (#{new_count} <= #{sign_count})" if rows.zero?
    reload
  end

  # Claims the kept -> discarded transition atomically, and audits only if this
  # caller won it. Returns whether it won.
  #
  # Discardable#discard! is an unconditional update!, so two requests that each
  # loaded a kept record both write a removal row: SQLite serializes the writers
  # but does not make the second re-read, and dirty tracking only ever sees that
  # instance's own stale nil (#826). This row is the only record that a passkey
  # was removed — no notifier corroborates it — so a duplicate misreports one
  # removal as two. The compare-and-swap is the same shape as
  # advance_sign_count! above, for the same reason.
  #
  # undiscard! then discard! is a genuine second removal and still audits: the
  # CAS predicate is satisfied again once discarded_at is back to nil.
  def discard!
    won = false

    transaction do
      claimed = self.class.where(id: id, discarded_at: nil)
                  .update_all(discarded_at: Time.current, updated_at: Time.current)
      next if claimed.zero?

      won = true
      reload
      audit!("user.passkey_removed")
    end

    won
  end

  private

  def audit_added = audit!("user.passkey_added")

  def audit!(action)
    ActivityLog.record_security_event!(action: action, user: user, metadata: { nickname: nickname })
  end
end
