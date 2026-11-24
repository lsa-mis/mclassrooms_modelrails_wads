class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Wider than ActiveStorage.web_image_content_types: HEIC/HEIF (the iPhone camera default) stay in.
  # One list for every image attachment, not per-model copies; see /docs/developer/security.
  IMAGE_CONTENT_TYPES = %w[
    image/png
    image/jpeg
    image/gif
    image/webp
    image/heic
    image/heif
  ].freeze

  # Assigns `attrs` (without saving) and reports whether that actually
  # changed anything — the shared "was this upsert a no-op?" check every
  # Sync:: phase's created/updated counting relies on (Task 7 of
  # planning/plans/phase-2-ingestion.md; roadmap Lib section). Call this
  # BEFORE the record's own #update!/#save!: that re-assigns the same attrs
  # harmlessly and persists, so a phase only counts :updated for a genuine
  # change, never a re-sync of identical data.
  def changed_after_assign(attrs)
    assign_attributes(attrs)
    changed?
  end
end
