# frozen_string_literal: true

# Lifecycle for Room#flat_panorama — the rectilinear render of Room#panorama.
#
# WHY THIS IS HERE AND NOT ON Room. The obvious home is a Room `after_commit`,
# and it is wrong in a way that is invisible until production:
#
#   * Attaching the render itself saves the Room, so a Room callback re-enqueues
#     the job that just ran (harmless, but every render costs three job runs).
#   * ActiveStorage::Blob has `after_update :touch_attachments`, and Attachment is
#     `belongs_to :record, touch: true`. So ANY write to blob metadata touches the
#     Room. The failure handler below writes blob metadata — under a Room callback
#     that is an unbounded loop: render fails, stamp, touch, enqueue, render fails.
#     It does not reproduce in dev (every panorama there is already valid) and it
#     does not reproduce under the :test adapter.
#   * A Room callback also fires for every unrelated edit, including the nightly
#     Sync::UpdateRooms pass over ~388 rooms.
#
# ActiveStorage::Attachment publishes exactly the event we want via
# `run_load_hooks :active_storage_attachment`, and it fires ONLY for the
# panorama slot. Do not move this to Room.
ActiveSupport.on_load(:active_storage_attachment) do
  after_create_commit :enqueue_flat_panorama_render,
                      if: -> { record_type == "Room" && name == "panorama" }

  # Replacing a panorama reassigns the `has_one :panorama_attachment,
  # dependent: :destroy` association, and Rails destroys the outgoing record —
  # so THIS hook fires on replace, purging the stale render and enqueueing a
  # fresh one (the pane falls back to :poster for the ~30ms in between).
  #
  # It does NOT cover explicit removal via `Room#remove_panorama=`. That path
  # calls `Attached::One#purge_later`, which delegates to
  # `Attachment#purge_later` — and that method deletes the attachment row with
  # `delete` (raw SQL), not `destroy`, so no destroy callback ever fires for
  # it. Explicit removal is handled directly in `Room#remove_panorama=`
  # (app/models/room.rb) instead; look there for that half.
  after_destroy_commit :purge_flat_panorama,
                       if: -> { record_type == "Room" && name == "panorama" }

  private

  def enqueue_flat_panorama_render
    RenderFlatPanoramaJob.perform_later(record_id)
  end

  # Re-read from the database rather than using `record`: the controller's Room
  # instance may have loaded flat_panorama as nil BEFORE a render attached it, and
  # purge_later on that stale association silently no-ops, leaving an orphan.
  def purge_flat_panorama
    Room.find_by(id: record_id)&.reload_flat_panorama_attachment&.purge_later
  end
end
