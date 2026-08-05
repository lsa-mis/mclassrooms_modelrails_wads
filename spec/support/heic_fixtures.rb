# frozen_string_literal: true

# Minimal HEIC/HEIF payloads for attachment content-type specs.
#
# Declaring `content_type: "image/heic"` on a PNG fixture does NOT produce a
# HEIC blob. Active Storage's `Blob#unfurl` runs `Marcel::MimeType.for` with
# `identify: true`, and Marcel sniffs the bytes and OVERRIDES the declared type
# whenever it recognises the signature — so PNG bytes persist as "image/png"
# no matter what the caller declared. A content-type spec written that way is
# vacuous: it exercises the `:png` entry that was always in the allowlist and
# stays green even if HEIC support is ripped out entirely.
#
# These are real ISO-BMFF container headers. Marcel identifies HEIC and HEIF
# from the `ftyp` box brand, so the bytes below are sniffed as the genuine
# article with no declared type needed at all — the validator sees a
# legitimately-identified image/heic. That is the whole file: a real phone HEIC
# is megabytes of HEVC payload that no validator ever reads, so there is
# nothing to gain from checking one into the repo.
module HeicFixtures
  HEIC_HEADER = "\x00\x00\x00\x18ftypheic\x00\x00\x00\x00heicmif1miaf".b.freeze
  HEIF_HEADER = "\x00\x00\x00\x18ftypmif1\x00\x00\x00\x00mif1heic".b.freeze

  # A fresh IO of HEIC container bytes, sniffed as "image/heic".
  def heic_io = StringIO.new(HEIC_HEADER.dup)

  # A fresh IO of HEIF container bytes, sniffed as "image/heif".
  def heif_io = StringIO.new(HEIF_HEADER.dup)
end

RSpec.configure do |config|
  config.include HeicFixtures
end
