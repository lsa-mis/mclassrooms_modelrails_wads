require "addressable/idna"

module EmailNormalizer
  module_function

  # Canonical email form: Unicode-NFC-normalized, stripped, downcased, domain
  # punycode-encoded. The local part is NOT punycoded — SMTPUTF8 (RFC 6531)
  # allows Unicode mailboxes, and IDNA does not apply there. Nil for blank input.
  # See /docs/developer/security (Canonical Email Keys).
  def normalize(email)
    return nil if email.nil? || email.to_s.strip.empty?

    canonicalized = email.to_s.unicode_normalize(:nfc).strip.downcase
    local, _, domain = canonicalized.rpartition("@")

    return canonicalized if local.empty? || domain.empty?

    "#{local}@#{punycode_domain(domain)}"
  end

  # Compares two emails for equality after canonical normalization. Returns
  # false if either side normalizes to a blank value.
  def equivalent?(a, b)
    a_norm = normalize(a)
    b_norm = normalize(b)
    a_norm.present? && a_norm == b_norm
  end

  # Returns the ASCII (punycode) form of a domain, falling back to the
  # original on conversion failure (malformed input, double-encoded values,
  # etc). Already-ASCII domains are returned unchanged.
  def punycode_domain(domain)
    Addressable::IDNA.to_ascii(domain)
  rescue StandardError
    domain
  end
end
