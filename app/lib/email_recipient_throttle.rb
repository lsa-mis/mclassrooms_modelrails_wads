# Per-recipient email throttle: caps sends of a given KIND to one address per
# sliding window. Gates by *recipient*, which per-user rate limits cannot — an
# attacker with N accounts stays under every per-user cap while flooding one
# victim inbox. Policy changes belong here, not at callsites.
# See /docs/developer/security (Per-Recipient Email Throttle).
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
