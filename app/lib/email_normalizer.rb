require "addressable/idna"

module EmailNormalizer
  module_function

  # Returns the canonical form of an email address: Unicode-NFC-normalized,
  # stripped, downcased, with the domain portion punycode-encoded.
  # Returns nil for blank input.
  #
  # Why NFC: visually identical strings can have different byte sequences
  # depending on Unicode form. The character "é" can be a single codepoint
  # U+00E9 (NFC) or "e" + combining acute U+0301 (NFD). User input via web
  # forms tends to be NFC; OAuth providers usually return NFC; but DB rows
  # imported from other systems or copy-pasted from PDFs may be NFD.
  # Normalizing both sides before comparison ensures equality holds.
  #
  # Why punycode the domain: DNS only speaks ASCII, so an IDN like
  # "user@bücher.de" gets punycode-encoded as "user@xn--bcher-kva.de" by
  # mail servers. A user might paste either form into a web form, but they
  # are the same address. Normalizing to the ASCII (punycode) form means
  # both representations share a single canonical key for storage and
  # comparison. Local part is NOT punycoded — SMTPUTF8 (RFC 6531) lets
  # mailboxes accept Unicode local parts, and IDNA does not apply there.
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
