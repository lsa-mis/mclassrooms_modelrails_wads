# frozen_string_literal: true

# Variants are warmed OFF the request path. Lazily generating them means the
# first cold load of a page with N images runs N synchronous vips transforms;
# on the import's ~1,362 assets that is minutes of CPU through a handful of
# Puma threads.
#
# Note the panorama spec's "VIPS_CONCURRENCY is moot" verdict does NOT carry
# over — that measured 227 sequential renders in a rake task, not ~5,400
# derivations.
#
# Enqueued from ActiveStorage::Attachment, not MediaAsset — see
# config/initializers/warm_media_variants.rb.
class WarmMediaVariantsJob < ApplicationJob
  queue_as :default

  def perform(asset)
    return unless asset&.image&.attached?

    %i[card thumb gallery full].each { |name| asset.image.variant(name).processed }
  rescue ActiveStorage::FileNotFoundError
    # The blob went away between enqueue and run. Nothing to warm.
    nil
  end
end
