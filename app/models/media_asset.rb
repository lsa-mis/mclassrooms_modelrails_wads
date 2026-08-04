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
  def derived_alt
    entry = owner_type.constantize::SUBJECTS[subject&.to_sym] if subject.present?
    return I18n.t("media.derived_alt.gallery_image", room: owner.media_owner_name) if entry.nil?

    I18n.t(entry.fetch(:key), owner: owner.media_owner_name)
  end

  private

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
