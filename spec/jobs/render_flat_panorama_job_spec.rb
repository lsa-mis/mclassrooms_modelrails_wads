require "rails_helper"

# Renders Room#panorama to the flat rectilinear view the pano pane serves.
#
# The enqueue hangs off ActiveStorage::Attachment, NOT Room — see
# config/initializers/flat_panorama_callbacks.rb for why (the Room version was
# an infinite loop). The source_blob_key + projection stamps make the job
# idempotent, which is what lets the backfill be a dumb re-run.
RSpec.describe RenderFlatPanoramaJob do
  include ActiveJob::TestHelper   # NOT globally included in this suite

  let(:workspace) { create(:workspace, slug: "flat-pano-ws", personal: false) }
  let(:building)  { create(:building, workspace: workspace) }
  let(:room)      { create(:room, :with_equirect_panorama, building: building, workspace: workspace) }

  before { clear_enqueued_jobs }

  def run = described_class.perform_now(room.id)

  describe "the attach hook" do
    it "enqueues a render when a panorama is attached" do
      bare = create(:room, building: building, workspace: workspace)

      expect {
        bare.panorama.attach(io: Rails.root.join("spec/fixtures/files/equirect.png").open,
                             filename: "p.png", content_type: "image/png")
      }.to have_enqueued_job(described_class).with(bare.id)
    end

    it "does not enqueue on an unrelated attribute change" do
      room && clear_enqueued_jobs

      expect { room.update!(nickname: "Renamed") }.not_to have_enqueued_job(described_class)
    end

    # The loop the Room-level callback created: attaching the DERIVED image must
    # not trigger another render.
    it "does not enqueue when the flat panorama itself is attached" do
      room && clear_enqueued_jobs

      expect {
        room.flat_panorama.attach(io: Rails.root.join("spec/fixtures/files/equirect.png").open,
                                  filename: "f.png", content_type: "image/png")
      }.not_to have_enqueued_job(described_class)
    end
  end

  describe "rendering" do
    it "renders the view and stamps the source key and the projection recipe" do
      run

      room.reload
      expect(room.flat_panorama).to be_attached
      expect(room.flat_panorama.blob.metadata["source_blob_key"]).to eq(room.panorama.blob.key)
      expect(room.flat_panorama.blob.metadata["projection"]).to eq(Panorama::Rectilinear.signature)
      expect(room.flat_panorama.blob.content_type).to eq("image/webp")
    end

    # Captured DURING the work, not after: asserting Current.workspace once the
    # job has returned passes even for an implementation that sets it on the
    # last line, after every tenant-scoped query has already run unscoped.
    it "establishes workspace context before doing any tenant-scoped work" do
      seen = nil
      allow(Panorama::Rectilinear).to receive(:render).and_wrap_original do |original, *args, **opts|
        seen = Current.workspace
        original.call(*args, **opts)
      end

      run

      expect(seen).to eq(workspace)
    end

    it "is a no-op when the view is already fresh" do
      run
      original = room.reload.flat_panorama.blob.id

      run

      expect(room.reload.flat_panorama.blob.id).to eq(original)
    end

    it "re-renders when the projection recipe changes" do
      run
      original = room.reload.flat_panorama.blob.id
      allow(Panorama::Rectilinear).to receive(:signature).and_return("hfov90-aspect2-w1024")

      run

      expect(room.reload.flat_panorama.blob.id).not_to eq(original)
    end

    # A Kamal SIGKILL between the attachment commit and the file upload leaves a
    # blob row with a correct stamp and NO FILE. Without this check the room
    # serves a 404 image forever and view_status calls it "up to date".
    it "re-renders when the stamped blob has no file on disk" do
      run
      blob = room.reload.flat_panorama.blob
      blob.service.delete(blob.key)

      run

      expect(room.reload.flat_panorama.blob.id).not_to eq(blob.id)
    end

    it "leaves exactly one attachment after repeated runs" do
      3.times { run }

      expect(ActiveStorage::Attachment.where(record: room.reload, name: "flat_panorama").count).to eq(1)
    end

    it "does nothing when no panorama is attached" do
      bare = create(:room, building: building, workspace: workspace)

      expect { described_class.perform_now(bare.id) }.not_to raise_error
      expect(bare.reload.flat_panorama).not_to be_attached
    end

    # discard_on is implemented with rescue_from, and perform_now runs rescue
    # handlers — so a discarded error is SWALLOWED here, not raised.
    it "discards a non-equirectangular source and records why" do
      square = create(:room, :with_panorama, building: building, workspace: workspace)

      expect { described_class.perform_now(square.id) }.not_to raise_error

      square.reload
      expect(square.flat_panorama).not_to be_attached
      expect(square.panorama.blob.metadata["flat_render_failed_at"]).to be_present
      expect(square.panorama.blob.metadata["flat_render_error"]).to match(/NotEquirectangular/)
    end

    it "does not retry a source already recorded as permanently failed" do
      square = create(:room, :with_panorama, building: building, workspace: workspace)
      described_class.perform_now(square.id)

      expect(Panorama::Rectilinear).not_to receive(:render)
      described_class.perform_now(square.id)
    end

    it "discards when the room no longer exists" do
      id = room.id
      room.destroy!

      expect { described_class.perform_now(id) }.not_to raise_error
    end

    # The panorama vanishing DURING the render (before the post-render reload
    # guard runs) hits the supersession `return` — flat_panorama is never
    # attached at all, so there's nothing to reconcile.
    it "discards output when the panorama is superseded mid-render" do
      allow(Panorama::Rectilinear).to receive(:render).and_wrap_original do |original, *args, **opts|
        result = original.call(*args, **opts)
        room.panorama.purge
        result
      end

      expect { run }.not_to raise_error
      expect(room.reload.flat_panorama).not_to be_attached
    end

    # The window between the post-render guard and the attach is real: the
    # metadata hash (which calls Panorama::Rectilinear.signature) is built and
    # the attach's `record.save` runs after the guard has already passed. If the
    # source vanishes there, the render DOES land, and the final reconcile must
    # purge it rather than leave an orphan no operator surface can see.
    #
    # The latch matters: `signature` is called by `fresh?` too, and an
    # unconditional purge here re-enters on every call. Purge exactly once, and
    # do NOT wrap this in perform_enqueued_jobs — the factory's own panorama
    # attach already enqueued a render, and performing it re-enters the stub.
    it "purges its own output if the panorama vanishes between the guard and the attach" do
      purged = false
      allow(Panorama::Rectilinear).to receive(:signature).and_wrap_original do |original, *args, **opts|
        unless purged
          purged = true
          room.panorama.purge
        end
        original.call(*args, **opts)
      end
      allow(Rails.logger).to receive(:info).and_call_original

      expect { run }.not_to raise_error

      expect(room.reload.flat_panorama).not_to be_attached
      expect(Rails.logger).to have_received(:info)
        .with(a_string_matching(/source purged mid-attach; output purged/))
    end

    # Attached::One#attach is `return if !record.save` — no bang — and
    # `attached?` reflects the pending in-memory change even when `save` just
    # returned false, so `attached?` alone can't detect a failed persist. A real
    # validation failure (not a stub of Active Storage) must still raise.
    it "raises when the room fails to save during attach, and leaves nothing attached" do
      # update_column bypasses validations/callbacks to plant a genuinely
      # invalid in-DB state (blank rmrecnbr) that only bites on the NEXT save —
      # the one triggered by flat_panorama.attach inside the job. A blank
      # string is a legal NOT NULL value at the DB layer (it isn't NULL), so
      # this trips only the `presence: true` validation, not the DB's unique
      # index on rmrecnbr the way reusing another room's value would.
      room.update_column(:rmrecnbr, "")

      expect { run }.to raise_error(/flat_panorama did not persist/)

      expect(Room.find(room.id).flat_panorama).not_to be_attached
    end
  end
end
