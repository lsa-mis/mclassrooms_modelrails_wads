# frozen_string_literal: true

require "rails_helper"

# Warms MediaAsset's four declared variants off the request path.
#
# The enqueue hangs off ActiveStorage::Attachment, NOT a MediaAsset
# after_commit — see config/initializers/warm_media_variants.rb for the
# blob-touch loop that rules out (the flat-panorama precedent).
RSpec.describe WarmMediaVariantsJob do
  include ActiveJob::TestHelper # NOT globally included in this suite

  let(:workspace) { create(:workspace, slug: "warm-variants-ws", personal: false) }
  let(:room)      { create(:room, workspace: workspace) }

  before { clear_enqueued_jobs }

  describe "#perform" do
    # The plan asserted `variant(name)` would `be_processed`, but
    # ActiveStorage::VariantWithRecord#processed? is PRIVATE in Rails 8.1, so
    # the predicate matcher cannot reach it. Probe the public surface instead:
    # a processed variant persists an ActiveStorage::VariantRecord keyed by
    # its variation digest.
    it "processes every declared variant so none is generated in-request" do
      asset = create(:media_asset, owner: room, workspace: workspace)

      described_class.perform_now(asset)

      digests = %i[card thumb gallery full].map { |name| asset.image.variant(name).variation.digest }
      expect(asset.image.blob.variant_records.pluck(:variation_digest)).to match_array(digests)
    end

    it "no-ops on an asset whose image is gone rather than raising" do
      asset = create(:media_asset, owner: room, workspace: workspace)
      asset.image.purge

      expect { described_class.perform_now(asset) }.not_to raise_error
    end

    # Purge deletes the attachment row too, so the example above returns at
    # the attached? guard and never reaches the FileNotFoundError rescue.
    # This one does reach it: blob row intact, file deleted underneath it —
    # what prod looks like when a blob's file goes missing between enqueue
    # and run.
    it "swallows FileNotFoundError when the blob row outlives the file" do
      asset = create(:media_asset, owner: room, workspace: workspace)
      blob = asset.image.blob
      blob.service.delete(blob.key)

      expect { described_class.perform_now(asset) }.not_to raise_error
      expect(blob.variant_records.count).to eq(0)
    end
  end

  describe "the attach hook" do
    it "enqueues a warm exactly once, with the asset, when a MediaAsset image is attached" do
      asset = nil
      expect { asset = create(:media_asset, owner: room, workspace: workspace) }
        .to have_enqueued_job(described_class).exactly(:once)

      warms = enqueued_jobs.select { |j| j[:job] == described_class }
      expect(warms.map { |j| j[:args].first["_aj_globalid"] }).to eq([ asset.to_global_id.to_s ])
    end

    # The gate's record_type conjunct is load-bearing on its own: the four
    # VariantRecord rows the warm creates each attach a blob under their own
    # `has_one_attached :image`, and those attachments are ALSO named "image".
    # Gating on the name alone re-enqueues once per variant — a second loop
    # vector. The Building example below cannot catch that (it is excluded by
    # name, not record_type); this one can.
    it "does not re-enqueue off the variant records the warm itself attaches" do
      asset = create(:media_asset, owner: room, workspace: workspace)
      clear_enqueued_jobs

      described_class.perform_now(asset)

      expect(enqueued_jobs.select { |j| j[:job] == described_class }).to be_empty
    end

    it "does not enqueue for a non-MediaAsset image slot" do
      building = create(:building, workspace: workspace)

      expect {
        building.photo.attach(io: Rails.root.join("spec/fixtures/files/avatar.png").open,
                              filename: "b.png", content_type: "image/png")
      }.not_to have_enqueued_job(described_class)
    end
  end
end
