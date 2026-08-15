# Per-recipient email throttle. Caps how many emails of a given KIND we'll send
# to a single email address within a sliding window — orthogonal to the per-user
# rate limits that already gate the controller actions that send mail.
#
# Why this exists: a per-user rate limit (`rate_limit by: -> { Current.user&.id }`)
# stops one attacker from spamming verification emails. It does not stop
# "Alice (attacker A) tries once, then Bob (attacker B) tries once, then Carol
# (attacker C) tries once..." — coordinated attack or attacker-with-N-accounts.
# The recipient (victim@example.com) sees N emails to their inbox even though
# every individual sender stayed under their per-user limit.
#
# This module gates by the *recipient* address. Counter lives in Rails.cache
# (Solid Cache in this project), keyed by SHA-256 of the canonical email +
# the kind (verification / collision_alert / etc). Independent buckets per
# kind so a flood of one type doesn't suppress legitimate sends of another.
#
# Default policy: 3 sends per recipient per kind per hour. Tightening or
# loosening should happen here, not at callsites.
module EmailRecipientThrottle
  module_function

  WINDOW = 1.hour
  CAP = 3

  # Per-kind overrides of the default policy (SEC-9). :magic_link is shared by
  # all four magic-link send endpoints (lookup sign-in + registration, resend,
  # password reset) — they all mint into ONE intent-blind supersede pool, so
  # they must share one budget or endpoint-hopping resets it. The window
  # matches the 15-minute token expiry: a throttled-out user is never stranded
  # longer than their newest link's lifetime, and an attacker gets at most
  # `cap` supersedes per window before the victim's link becomes untouchable.
  KIND_POLICIES = {
    magic_link: { cap: 5, window: 15.minutes }
  }.freeze

  # Atomically increments the recipient's counter for the given kind, then
  # returns true if the send is allowed (count <= cap after increment) or
  # false if the cap was exceeded.
  #
  # Fail-open semantics: if Rails.cache.increment returns nil (cache backend
  # unavailable, or driver doesn't support increment), this returns true.
  # Email delivery is more important than the throttle in a degraded state.
  def allow!(email, kind:)
    policy = KIND_POLICIES.fetch(kind, { cap: CAP, window: WINDOW })
    key = cache_key(email, kind)
    count = Rails.cache.increment(key, 1, expires_in: policy[:window])
    return true if count.nil?
    count <= policy[:cap]
  end

  # Reset the counter for testing. Not used in production code paths.
  def reset!(email, kind:)
    Rails.cache.delete(cache_key(email, kind))
  end

  def cache_key(email, kind)
    normalized = EmailNormalizer.normalize(email).to_s
    digest = Digest::SHA256.hexdigest(normalized)
    "email_recipient_throttle:#{kind}:#{digest}"
  end
end
