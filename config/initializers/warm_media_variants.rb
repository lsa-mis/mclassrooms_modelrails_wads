# frozen_string_literal: true

# Warm MediaAsset's declared variants the moment an image is attached, so no
# visitor pays for the first vips transform in-request.
#
# WHY THIS IS HERE AND NOT ON MediaAsset. The obvious home is a MediaAsset
# `after_commit`, and it is wrong in a way that is invisible until production:
# ActiveStorage::Blob has `after_update :touch_attachments`, and Attachment is
# `belongs_to :record, touch: true`, so ANY write to blob metadata touches the
# owning record. Warming writes variant state against the blob — under a
# MediaAsset callback that is an unbounded loop (warm → blob touched → asset
# touched → warm), green under the :test adapter and invisible in dev. The
# panorama work ran twelve waves before converging on this mechanism; see
# config/initializers/flat_panorama_callbacks.rb, the precedent this follows.
#
# Fires for exactly the MediaAsset image slot. Attaching a VARIANT does not
# re-trigger it — a variant's file is attached to an
# ActiveStorage::VariantRecord row, not to MediaAsset — so this terminates
# where the after_commit would not.
ActiveSupport.on_load(:active_storage_attachment) do
  after_create_commit :enqueue_media_variant_warm,
                      if: -> { record_type == "MediaAsset" && name == "image" }

  private

  def enqueue_media_variant_warm
    WarmMediaVariantsJob.perform_later(record)
  end
end
