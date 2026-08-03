require "vips"   # Vips::Error is named in the class body below, and ruby-vips is
                 # `require: false` in the Gemfile. Production eager-loads jobs, so
                 # without this the app fails to BOOT, not to render.

# Renders Room#panorama to Room#flat_panorama — the rectilinear view the pano
# pane serves before a visitor opts into the 360 viewer.
#
# Enqueued from ActiveStorage::Attachment, not Room — see
# config/initializers/flat_panorama_callbacks.rb.
#
# queue_as :low — CPU-bound native work sharing a host with Puma, and best-effort
# by definition (the pane falls back to :poster). Per config/queue.yml this is an
# OBSERVABILITY signal, not isolation.
#
# Current.workspace: Room is Tenanted with no default_scope, so nothing scopes
# this job's queries automatically (CLAUDE.md deviation #1).
#
# Measured: ~30-47ms per render, ~40KB out. The whole 219-room backfill is ~11s.
class RenderFlatPanoramaJob < ApplicationJob
  queue_as :low

  # SQLite's busy timeout surfaces as StatementTimeout, NOT Vips::Error — 219
  # short write transactions against a single writer shared with Puma.
  retry_on ActiveRecord::StatementTimeout, ActiveRecord::LockWaitTimeout,
           wait: :polynomially_longer, attempts: 5

  retry_on Vips::Error, wait: :polynomially_longer, attempts: 3 do |job, error|
    record_failure(job, error)
  end

  discard_on(ActiveRecord::RecordNotFound) do |job, _error|
    Rails.logger.info("[flat_panorama] room_id=#{job.arguments.first} gone before render; discarded")
  end

  # blob.open can hit a source the PurgeJob already deleted.
  discard_on(ActiveStorage::FileNotFoundError) do |job, _error|
    Rails.logger.info("[flat_panorama] room_id=#{job.arguments.first} source file missing; discarded")
  end

  discard_on(Panorama::Rectilinear::NotEquirectangular) { |job, error| record_failure(job, error) }

  # Records a PERMANENT failure on the source blob so it is answerable from the
  # console and from `panoramas:flat_status`. Mission Control is not mounted, so
  # a job that dies into solid_queue_failed_executions is otherwise invisible.
  #
  # Writing blob metadata touches the Room (Blob#touch_attachments). That is safe
  # ONLY because the enqueue hangs off the attachment — under a Room callback this
  # method was an infinite loop. Do not move the enqueue.
  def self.record_failure(job, error)
    room = Room.find_by(id: job.arguments.first)
    return unless room&.panorama&.attached?

    Rails.logger.warn("[flat_panorama] room=#{room.rmrecnbr} blob=#{room.panorama.blob.key} " \
                      "render permanently failed: #{error.class}: #{error.message}")
    room.panorama.blob.update!(
      metadata: room.panorama.blob.metadata.merge(
        "flat_render_failed_at"  => Time.current.iso8601,
        "flat_render_source_key" => room.panorama.blob.key,
        "flat_render_error"      => "#{error.class}: #{error.message}"
      )
    )
  end

  def perform(room_id)
    room = Room.find(room_id)
    Current.workspace = room.workspace

    return Rails.logger.info("[flat_panorama] room=#{room.rmrecnbr} no panorama; skipped") unless
      room.panorama.attached?

    source_key = room.panorama.blob.key
    return if fresh?(room, source_key) || permanently_failed?(room, source_key)

    bytes = room.panorama.blob.open { |file| Panorama::Rectilinear.render(file.path) }

    # The panorama can be REPLACED or PURGED during the ~30ms render. Attaching a
    # replaced source's output would stamp a view of the old blob, and the
    # replacement's own job has already run — a permanently stale render with
    # nothing left to correct it.
    room.reload
    unless room.panorama.attached? && room.panorama.blob.key == source_key
      Rails.logger.info("[flat_panorama] room=#{room.rmrecnbr} superseded mid-render; output discarded")
      return
    end

    room.flat_panorama.attach(
      io: bytes, filename: "#{room.rmrecnbr}-flat.webp", content_type: "image/webp",
      metadata: { "source_blob_key" => source_key,
                  "projection" => Panorama::Rectilinear.signature }
    )

    # Attached::One#attach is `return if !record.save` — no bang. A Room invalid
    # for any unrelated reason fails SILENTLY: no attachment, no exception, no
    # failed execution. PanoramaIngest#attach guards the same trap the same way.
    raise "flat_panorama did not persist: #{room.errors.full_messages.join('; ').presence || 'unknown'}" unless
      room.flat_panorama.attached?

    # Last reconcile: if the source vanished between the guard and here, purge our
    # own output rather than leaving an orphan no operator surface can see.
    if room.reload.panorama.attached?
      Rails.logger.info("[flat_panorama] room=#{room.rmrecnbr} rendered from #{source_key}")
    else
      room.flat_panorama.purge_later
      Rails.logger.info("[flat_panorama] room=#{room.rmrecnbr} source purged mid-attach; output purged")
    end
  end

  private

  def fresh?(room, source_key)
    flat = room.flat_panorama
    return false unless flat.attached?
    return false unless flat.blob.metadata["source_blob_key"] == source_key
    return false unless flat.blob.metadata["projection"] == Panorama::Rectilinear.signature
    # A SIGKILL between the attachment commit and the file upload leaves a blob row
    # with a correct stamp and NO FILE, and every check downstream then lies the
    # same way: attached? is true, so :poster never engages and the page serves a
    # 404 image forever. One stat call closes it.
    return false unless flat.blob.service.exist?(flat.blob.key)

    Rails.logger.info("[flat_panorama] room=#{room.rmrecnbr} fresh (#{source_key}); skipped")
    true
  end

  # Without this a non-2:1 room re-downloads its full source on every enqueue,
  # forever, to re-raise the same error. Keyed on the source blob so replacing the
  # bad photo with a good one clears the tombstone.
  def permanently_failed?(room, source_key)
    meta = room.panorama.blob.metadata
    meta["flat_render_failed_at"].present? && meta["flat_render_source_key"] == source_key
  end
end
