# frozen_string_literal: true

# One home for the repeatable images a record owns. Rooms are the first owner;
# Buildings are expected next, which is why `owner` is polymorphic and the
# subject vocabulary is declared by the owner rather than here.
#
# There is deliberately NO generic concern wrapping this (see the spec's "The
# concern, and why it is gone"): one consumer does not clear the project's
# 3+-models bar, and the extraction target is a view-primitives gem that cannot
# host a model.
class MediaAsset < ApplicationRecord
  include Tenanted
  include Describable

  # Raised from base_derived_alt rather than emitted: a blank media_owner_name
  # interpolated into an alt string still reads as `be_present` (a trailing
  # preposition and nothing after it), which is invisible to the shipped
  # ratchet but incoherent to a screen-reader user. Failing loudly routes the
  # problem to a developer instead of shipping it to the one person who can
  # least route around it.
  class BlankOwnerName < StandardError; end

  belongs_to :owner, polymorphic: true

  # Every variant is webp so a HEIC upload renders anywhere. Declared HERE, once
  # — not per owner — because consumers choosing their own sizes is how the
  # ~219 orphaned VariantRecords accumulated during the panorama work.
  has_one_attached :image do |attachable|
    attachable.variant :card,    resize_to_fill:  [ 96, 96 ],     format: :webp
    attachable.variant :thumb,   resize_to_limit: [ 200, 200 ],   format: :webp
    attachable.variant :gallery, resize_to_limit: [ 800, 800 ],   format: :webp
    attachable.variant :full,    resize_to_limit: [ 1600, 1600 ], format: :webp
  end

  validates :position, numericality: { greater_than_or_equal_to: 1 }
  validates :image, attached: true,
                    content_type: [ :png, :jpeg, :webp, "image/heic", "image/heif" ],
                    size: { less_than_or_equal_to: 10.megabytes }
  validate :owner_must_share_workspace
  # App-level only, deliberately. A table CHECK would have to union every owner
  # type's vocabulary (so a Building subject would validate on a Room row), and
  # SQLite rebuilds the table to drop a constraint — while the vocabulary is
  # designed to churn. Resolved from owner_type, not owner, so a missing owner
  # row cannot raise inside a validation.
  validate :subject_must_be_in_owner_vocabulary

  # Ranking by subject happens in Ruby over the preloaded collection — see
  # Room#gallery_ordered (Task 7). A SQL CASE would re-query and defeat the
  # eager load (the reason lib/bullet_safelists.rb carries a gallery entry at all).
  scope :ordered, -> { order(:position, :id) }

  describable :image, derived_alt: ->(rec) { rec.derived_alt }

  # Resolved through the OWNER's vocabulary. An unrecognised or retired subject
  # degrades to the generic string rather than raising: this is alt text, and a
  # KeyError here is a 500 on a screen-reader user's page.
  #
  # Subjects are repeatable (a room can have two racks), so two assets in one
  # gallery can derive byte-identical strings. Suffix positionally in that
  # case — only among UNAUTHORED siblings, and only when there are 2+ of them,
  # so an authored image_alt is never suffixed and a lone match isn't either.
  def derived_alt
    base = base_derived_alt
    # `owner.gallery` is an association loaded from the database, so it never
    # contains a not-yet-persisted `self` — union it in explicitly rather than
    # assume it is already there. `|` de-duplicates via AR's id-based `eql?`,
    # so a persisted `self` already present in the collection is not counted
    # twice.
    candidates = owner.gallery.select { |a| a.image_alt.blank? && a.subject == subject } | [ self ]
    return base if candidates.length < 2

    # `a.id || Float::INFINITY`: the same unsaved/persisted-tie hazard
    # Room#gallery_ordered guards against — an unsaved sibling has a nil id,
    # and `nil <=> Integer` breaks `sort_by`'s Array comparison.
    ordered = candidates.sort_by { |a| [ a.position, a.id || Float::INFINITY ] }
    I18n.t("media.derived_alt.nth", alt: base, n: ordered.index(self) + 1, total: ordered.length)
  end

  private

  def base_derived_alt
    name = owner.media_owner_name
    raise BlankOwnerName, "#{owner_type}##{owner_id} has a blank media_owner_name" if name.blank?

    entry = owner_type.constantize::SUBJECTS[subject&.to_sym] if subject.present?
    return I18n.t("media.derived_alt.gallery_image", room: name) if entry.nil?

    I18n.t(entry.fetch(:key), owner: name)
  end

  # The polymorphic move drops the room FK, and Tenanted only requires a
  # workspace to be present — nothing otherwise stops an asset in workspace A
  # hanging off an owner in workspace B, readable through the wrong index.
  def owner_must_share_workspace
    return if owner.nil? || workspace_id.nil?
    return if owner.workspace_id == workspace_id

    errors.add(:owner, :workspace_mismatch)
  end

  def subject_must_be_in_owner_vocabulary
    return if subject.blank? || owner_type.blank?

    vocabulary = owner_type.constantize::SUBJECTS
    return if vocabulary.key?(subject.to_sym)

    errors.add(:subject, :inclusion)
  end
end
