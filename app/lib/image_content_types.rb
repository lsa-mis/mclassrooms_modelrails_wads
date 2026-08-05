# The single source of truth for which image content types an upload slot
# accepts. Hand-duplicated across five validations until Task 10 fix round 2 —
# five lists that had to move in lockstep if a type is ever pruned for
# security (config/initializers/active_storage.rb carries a CVE remediation;
# the risk is real). A bare frozen constant, deliberately NOT a concern: the
# "concerns for 3+ models" rule is about shared behavior, and this is data.
#
# HEIC/HEIF are accepted because they are what phones actually produce; no
# display path may serve one raw (browsers cannot decode them), so every
# render goes through a declared webp variant — see Room/Floor/MediaAsset.
module ImageContentTypes
  ACCEPTED = [ :png, :jpeg, :webp, "image/heic", "image/heif" ].freeze
  # Slots that also take a document (seating charts, floor plans). A PDF is
  # never variant-transcoded — the PDF-guarded view branches link the
  # original blob inline.
  ACCEPTED_WITH_PDF = (ACCEPTED + [ :pdf ]).freeze
end
