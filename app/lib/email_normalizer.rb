module EmailNormalizer
  module_function

  # Returns the canonical form of an email address: Unicode-NFC-normalized,
  # downcased, and stripped. Returns nil for blank input.
  #
  # Why NFC: visually identical strings can have different byte sequences
  # depending on Unicode form. The character "é" can be a single codepoint
  # U+00E9 (NFC) or "e" + combining acute U+0301 (NFD). User input via web
  # forms tends to be NFC; OAuth providers usually return NFC; but DB rows
  # imported from other systems or copy-pasted from PDFs may be NFD.
  # Normalizing both sides before comparison ensures equality holds.
  #
  # Note: this does NOT perform IDN (Internationalized Domain Name)
  # punycode conversion (e.g., "bücher.de" ↔ "xn--bcher-kva.de"). That
  # requires an additional dependency such as the `addressable` gem and
  # is deferred unless a real interop concern surfaces. NFC is the
  # realistic case for almost all user-facing inputs.
  def normalize(email)
    return nil if email.nil? || email.to_s.strip.empty?
    email.to_s.unicode_normalize(:nfc).strip.downcase
  end

  # Compares two emails for equality after canonical normalization. Returns
  # false if either side normalizes to a blank value.
  def equivalent?(a, b)
    a_norm = normalize(a)
    b_norm = normalize(b)
    a_norm.present? && a_norm == b_norm
  end
end
