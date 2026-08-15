# Vips::Error is named in the class body below, and ruby-vips is
# `require: false` in the Gemfile. Production eager-loads jobs, so without this
# the app fails to BOOT, not to render.
require "vips"

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

  # SQLite's busy timeout surfaces as StatementTimeout and NOTHING else — 219
  # short write transactions against a single writer shared with Puma.
  # ActiveRecord::LockWaitTimeout is deliberately absent: SQLite3Adapter's
  # `translate_exception` maps ::SQLite3::BusyException to StatementTimeout
  # only (activerecord/.../sqlite3_adapter.rb), so listing LockWaitTimeout here
  # was dead code that misdescribed the failure mode to the next reader.
  retry_on ActiveRecord::StatementTimeout, wait: :polynomially_longer, attempts: 5

  # attempts: 2, not more. A decode failure on a FIXED blob is deterministic —
  # the same bytes decode the same way every time — so extra attempts only buy
  # another full download + tempfile + MD5 + decode each. Two still covers the
  # one non-deterministic case worth covering: a transient ENOMEM when several
  # renders and Puma contend for the same host.
  retry_on Vips::Error, wait: :polynomially_longer, attempts: 2 do |job, error|
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

  # The blob key this run actually rendered FROM. Captured on the instance in
  # `perform` and read back by the class-level failure handlers, which run after
  # the fact and must not re-derive it from the database — see `record_failure`.
  attr_reader :source_key

  # Records a PERMANENT failure on the source blob so it is answerable from the
  # console and from `panoramas:flat_status`. Mission Control is not mounted, so
  # a job that dies into solid_queue_failed_executions is otherwise invisible.
  #
  # Writing blob metadata touches the Room (Blob#touch_attachments). That is safe
  # ONLY because the enqueue hangs off the attachment — under a Room callback this
  # method was an infinite loop. Do not move the enqueue.
  #
  # KEYED TO job.source_key, NEVER to a re-read of whatever is attached now.
  # The interleaving this rules out is not exotic: a 4:3 photo fails with
  # NotEquirectangular; an admin replaces it with the correct 2:1 equirect,
  # which is a new attachment and enqueues its own job; THIS handler then runs
  # and, re-reading, would stamp the brand-new VALID blob as permanently
  # failed. The replacement's own job would see `flat_render_failed?` and skip,
  # `candidates` would exclude the room from every backfill, and the failure
  # report would tell the operator to replace the photo — which is exactly what
  # they had just done. A valid panorama, tombstoned forever.
  def self.record_failure(job, error)
    room = Room.find_by(id: job.arguments.first)
    return unless room&.panorama&.attached?

    current_key = room.panorama.blob.key
    if current_key != job.source_key
      return Rails.logger.info(
        "[flat_panorama] room=#{room.rmrecnbr} source moved since this render began " \
        "(#{job.source_key.inspect} -> #{current_key}); failure NOT recorded — the " \
        "replacement's own render owns the outcome"
      )
    end

    Rails.logger.warn("[flat_panorama] room=#{room.rmrecnbr} blob=#{job.source_key} " \
                      "render permanently failed: #{error.class}: #{error.message}")
    room.panorama.blob.update!(
      metadata: room.panorama.blob.metadata.merge(
        "flat_render_failed_at"  => Time.current.iso8601,
        "flat_render_source_key" => job.source_key,
        "flat_render_error"      => "#{error.class}: #{error.message}"
      )
    )
  end

  def perform(room_id)
    room = Room.find(room_id)

    # `set`, not a bare assignment: an INLINE backfill runs every room in one
    # process, and a plain `Current.workspace =` would leave the LAST room's
    # workspace set for whatever runs after the task.
    Current.set(workspace: room.workspace) { render_flat(room) }
  end

  private

  def render_flat(room)
    return Rails.logger.info("[flat_panorama] room=#{room.rmrecnbr} no panorama; skipped") unless
      room.panorama.attached?

    # Captured on the instance so the class-level failure handlers can stamp the
    # blob this run rendered FROM rather than re-reading the association.
    @source_key = room.panorama.blob.key

    if room.flat_render_current?
      return Rails.logger.info("[flat_panorama] room=#{room.rmrecnbr} fresh (#{source_key}); skipped")
    end
    # Without this a non-2:1 room re-downloads its full source on every enqueue,
    # forever, to re-raise the same error.
    return if room.flat_render_failed?

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

    attach_and_verify!(room, bytes)
  end

  def attach_and_verify!(room, bytes)
    room.flat_panorama.attach(
      io: bytes, filename: "#{room.rmrecnbr}-flat.webp", content_type: "image/webp",
      metadata: { "source_blob_key" => source_key,
                  "projection" => Panorama::Rectilinear.signature }
    )

    # Attached::One#attach is `return if !record.save` — no bang. A Room invalid
    # for any unrelated reason fails SILENTLY: no attachment, no exception, no
    # failed execution. PanoramaIngest#attach guards the same trap the same way.
    #
    # `room.flat_panorama.attached?` alone is NOT enough: Attached::One#attached?
    # is `attachment.present?`, and `#attachment` returns the pending in-memory
    # CreateOne change whenever one exists — `attachment_changes[name]` is only
    # cleared on `after_commit` or `reload`. So after a failed `save`, the
    # built-but-unsaved attachment is still `present?` and `attached?` lies true.
    # `room.errors.empty?` is the half that actually detects the silent failure.
    unless room.errors.empty? && room.flat_panorama.attached?
      message = room.errors.full_messages.join("; ").presence || "unknown"
      Rails.logger.error("[flat_panorama] room=#{room.rmrecnbr} flat_panorama did not persist: #{message}")
      raise "flat_panorama did not persist: #{message}"
    end

    # Last reconcile: if the source vanished between the guard and here, purge our
    # own output rather than leaving an orphan no operator surface can see.
    if room.reload.panorama.attached?
      Rails.logger.info("[flat_panorama] room=#{room.rmrecnbr} rendered from #{source_key}")
    else
      room.flat_panorama.purge_later
      Rails.logger.info("[flat_panorama] room=#{room.rmrecnbr} source purged mid-attach; output purged")
    end
  end
end
