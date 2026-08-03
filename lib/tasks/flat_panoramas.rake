# Backfill + operator surface for the flat (rectilinear) panorama renders.
#
#   bin/rails panoramas:render_flat                      # enqueue every missing/stale room
#   bin/rails panoramas:render_flat DRY_RUN=1            # report only, touch nothing
#   bin/rails panoramas:render_flat ROOM=12345 INLINE=1 FORCE=1   # the diagnostic loop
#   bin/rails panoramas:render_flat INLINE=1             # render in-process (~11s for 219)
#   bin/rails panoramas:flat_status                      # read-only counts
#
# INLINE bypasses the queue entirely — it does NOT enqueue and wait.
# Run the backfill AFTER a deploy settles: config/deploy.yml sets a 45s drain
# window with SOLID_QUEUE_IN_PUMA, so in-flight jobs are SIGKILLed. Idempotence
# makes a re-run safe.
namespace :panoramas do
  desc "Render missing/stale flat panoramas (DRY_RUN=1 ROOM=rmrecnbr FORCE=1 INLINE=1 LIMIT=n WORKSPACE=slug)"
  task render_flat: :environment do
    workspace = FlatPanoramaTasks.workspace!
    dry_run, inline, force = ENV["DRY_RUN"].present?, ENV["INLINE"].present?, ENV["FORCE"].present?

    scope      = FlatPanoramaTasks.scope(workspace, room: ENV["ROOM"].presence)
    candidates = FlatPanoramaTasks.candidates(scope, force: force)
    backlog    = candidates.size
    candidates = candidates.first(ENV["LIMIT"].to_i) if ENV["LIMIT"].present?

    # Always print the denominator: "0 to render" is otherwise the same string
    # whether nothing has a panorama, everything is fresh, or WORKSPACE resolved
    # to the wrong tenant.
    puts "workspace:     #{workspace.slug} (id #{workspace.id})"
    puts "with panorama: #{scope.count}"
    puts "to render:     #{candidates.size} of #{backlog} stale/missing" \
         "#{' (dry run)' if dry_run}#{' [FORCE]' if force}"

    rendered, failed = [], []
    candidates.each do |room|
      next if dry_run

      begin
        # See FlatPanoramaTasks.clear_tombstone! — FORCE has to defeat the
        # job's own permanently_failed? guard here, before the job ever runs,
        # or a previously-failed room stays silently skipped forever.
        FlatPanoramaTasks.clear_tombstone!(room) if force
        inline ? RenderFlatPanoramaJob.perform_now(room.id) : RenderFlatPanoramaJob.perform_later(room.id)
        rendered << room
      rescue StandardError => e
        failed << [ room, e ]
      end
    end

    FlatPanoramaTasks.write_report(workspace, rendered, failed, dry_run: dry_run, inline: inline)
    puts "#{inline ? 'rendered' : 'enqueued'}: #{rendered.size}   failed: #{failed.size}"
    puts inline ? "report: tmp/flat_panoramas/" : "nothing has RUN yet — check `panoramas:flat_status` after the queue drains"
  end

  desc "Count rooms with missing, stale, failed, or orphaned flat panoramas (WORKSPACE=slug)"
  task flat_status: :environment do
    workspace = FlatPanoramaTasks.workspace!
    rooms = FlatPanoramaTasks.scope(workspace).to_a

    stale  = FlatPanoramaTasks.candidates(rooms, force: false)
    failed = rooms.select { |r| r.panorama.blob.metadata["flat_render_failed_at"].present? }
    # A room with a render and NO panorama — the orphan the lifecycle exists to
    # prevent. Invisible to every other count here, because they all scope to
    # rooms that HAVE a panorama.
    orphans = Room.where(workspace: workspace)
                  .joins(:flat_panorama_attachment).where.missing(:panorama_attachment).count

    puts "workspace:     #{workspace.slug}"
    puts "with panorama: #{rooms.size}"
    puts "missing/stale: #{stale.size}"
    puts "failed render: #{failed.size}"
    puts "orphaned flat: #{orphans}"
    failed.first(10).each { |r| puts "  #{r.rmrecnbr}  #{r.panorama.blob.metadata['flat_render_error']}" }
  end
end

# Shared helpers, so "stale" has exactly ONE definition — if render_flat and
# flat_status disagreed, the status output would be a lie.
module FlatPanoramaTasks
  module_function

  def workspace!
    ws = ENV["WORKSPACE"].present? ? Workspace.find_by!(slug: ENV["WORKSPACE"]) : TenancyConfig.shared_workspace
    abort "No shared workspace resolved — pass WORKSPACE=<slug>" if ws.nil?
    ws
  end

  # distinct: schema.rb's uniqueness index is on (record_type, record_id, name,
  # blob_id), so it does NOT prevent two "panorama" rows with different blobs.
  # includes: without it this is ~4 lazy loads per room, ~880 queries at 219 rooms
  # (and Bullet runs in-process during the specs).
  def scope(workspace, room: nil)
    scope = Room.where(workspace: workspace)
                .joins(:panorama_attachment).distinct
                .includes(panorama_attachment: :blob, flat_panorama_attachment: :blob)
    room.present? ? scope.where(rmrecnbr: room) : scope
  end

  # source_key is read UNCONDITIONALLY, even on the `next true` branches that
  # do not need it, so the eager-loaded panorama_attachment: :blob is always
  # touched. Reading it only on the branch that needs it is correct-looking
  # but wrong: on a fresh backfill (the common case — flat_panorama never
  # attached) not one candidate ever reaches that branch, so Bullet flags the
  # whole `includes(panorama_attachment: :blob)` as unused eager loading for
  # the entire run.
  def candidates(scope, force: false)
    scope.select do |room|
      source_key = room.panorama.blob.key
      next true if force
      next true unless room.flat_panorama.attached?

      blob = room.flat_panorama.blob
      blob.metadata["source_blob_key"] != source_key ||
        blob.metadata["projection"] != Panorama::Rectilinear.signature
    end
  end

  # FORCE means "clear tombstones and re-render". Two independent guards on
  # RenderFlatPanoramaJob would otherwise silently no-op this call — force
  # only widens which rooms are SELECTED as candidates (see `next true if
  # force` above); it does nothing about what the job itself does once
  # invoked:
  #
  #   * #permanently_failed? — keyed on the SOURCE (panorama) blob's
  #     flat_render_failed_at/_source_key/_error stamps, set by the job's
  #     discard_on handler after a permanent failure (e.g. a non-equirect
  #     photo). Left in place, a broken room stays broken until its photo is
  #     replaced — the tombstone is otherwise unclearable.
  #   * #fresh? — keyed on the flat_panorama blob's OWN source_blob_key/
  #     projection stamps. Left in place, FORCE-ing an already-current render
  #     is a no-op — which defeats FORCE for the single most common
  #     diagnostic use (Panorama::Rectilinear.render.rb's own comment:
  #     `ROOM=<rmrecnbr> INLINE=1 FORCE=1` to re-render after a code change,
  #     where the SOURCE hasn't changed at all).
  #
  # Both guards belong in the JOB, not here — they are what stop an enqueue
  # storm (every unrelated Room write re-enqueues via config/initializers/
  # flat_panorama_callbacks.rb) from re-attempting a hopeless or redundant
  # render on every commit. Only an operator explicitly passing FORCE to THIS
  # task should be able to override them, so the override happens here,
  # immediately before the one deliberate invocation FORCE asked for.
  #
  # Deletes keys outright, not a merge with nils — `metadata.merge(key =>
  # nil)` would leave the key present with a nil value, a different (and
  # permanent) shape in the blob's metadata JSON than the key never having
  # existed.
  def clear_tombstone!(room)
    panorama_blob = room.panorama.blob
    if panorama_blob.metadata.key?("flat_render_failed_at")
      panorama_blob.update!(metadata: panorama_blob.metadata.except(
        "flat_render_failed_at", "flat_render_source_key", "flat_render_error"
      ))
    end

    return unless room.flat_panorama.attached?

    flat_blob = room.flat_panorama.blob
    return unless flat_blob.metadata.key?("source_blob_key") || flat_blob.metadata.key?("projection")

    flat_blob.update!(metadata: flat_blob.metadata.except("source_blob_key", "projection"))
  end

  def write_report(workspace, rendered, failed, dry_run:, inline:)
    return if dry_run

    dir = Rails.root.join("tmp/flat_panoramas")
    FileUtils.mkdir_p(dir)
    stamp = Time.current.strftime("%Y-%m-%d %H:%M %Z")
    state = inline ? "RENDERED" : "ENQUEUED (not yet run)"

    File.write(dir.join("flat_failed.txt"), <<~HEADER + failed.map { |r, e| "#{r.rmrecnbr}\t#{e.class}: #{e.message}" }.join("\n") + "\n")
      # Flat panorama renders that FAILED in workspace "#{workspace.slug}"
      # #{stamp} — #{failed.size} failures#{inline ? '' : ' (queued mode: jobs have NOT run; this file cannot report their failures — use panoramas:flat_status)'}
      # Remedy: replace the room's panorama with the 2:1 mi_locations equirect
      # export, or clear it. Until then the room serves the :poster fallback —
      # degraded (a squashed strip) but not broken.
    HEADER

    File.write(dir.join("flat_#{inline ? 'rendered' : 'enqueued'}.txt"),
               "# #{state} in workspace \"#{workspace.slug}\"\n# #{stamp} — #{rendered.size} rooms\n" +
               rendered.map(&:rmrecnbr).join("\n") + "\n")
  end
end
