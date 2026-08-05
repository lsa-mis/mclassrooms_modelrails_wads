class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Content types accepted for user-supplied images (avatars, workspace logos).
  #
  # Deliberately WIDER than ActiveStorage.web_image_content_types, which is the
  # set a browser renders directly. Rails converts a variant of anything outside
  # that set to PNG automatically, so the constraint that matters here is "can we
  # process it safely", not "can a browser display it".
  #
  # HEIC/HEIF are the iPhone camera default, so excluding them bounced the single
  # most common source of an avatar or logo upload — for no security benefit.
  # config/initializers/active_storage.rb records that both load and transform
  # under Vips.block_untrusted(true) after CVE-2026-66066, and both remain in
  # variable_content_types. Confirmed in the production base image too: Debian's
  # libvips 8.16.1 in ruby:slim ships heifload and heifsave.
  #
  # Shared rather than repeated per model: one list guards four attachments
  # across two models, and a copy per call site is how #496's drift happened.
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
