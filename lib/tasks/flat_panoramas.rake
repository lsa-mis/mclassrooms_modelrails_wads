# Backfill + operator surface for the flat (rectilinear) panorama renders.
#
#   bin/rails panoramas:render_flat                      # enqueue every missing/stale room
#   bin/rails panoramas:render_flat DRY_RUN=1            # report only, touch nothing
#   bin/rails panoramas:render_flat ROOM=12345 INLINE=1 FORCE=1   # the diagnostic loop
#   bin/rails panoramas:render_flat INLINE=1             # render in-process (~11s for 219)
#   bin/rails panoramas:flat_status                      # read-only counts
#
# INLINE bypasses the queue entirely — it does NOT enqueue and wait. INLINE
# outcomes are classified from the room's state AFTER each render, not from
# whether perform_now raised — see FlatPanoramaTasks.render_outcome.
#
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

    limit      = FlatPanoramaTasks.parse_limit!(ENV["LIMIT"])
    candidates = candidates.first(limit) if limit

    # Always print the denominator: "0 to render" is otherwise the same string
    # whether nothing has a panorama, everything is fresh, or WORKSPACE resolved
    # to the wrong tenant.
    puts "workspace:     #{workspace.slug} (id #{workspace.id})"
    puts "with panorama: #{scope.count}"
    puts "to render:     #{candidates.size} of #{backlog} stale/missing" \
         "#{' (dry run)' if dry_run}#{' [FORCE]' if force}"

    # Four buckets, not two. RenderFlatPanoramaJob absorbs virtually
    # everything it can raise — discard_on(NotEquirectangular),
    # discard_on(ActiveStorage::FileNotFoundError), discard_on(RecordNotFound),
    # and retry_on(Vips::Error) with a give-up block all handle their own
    # errors without re-raising, and its fresh?/permanently_failed? guards
    # return silently too. So "perform_now did not raise" proves nothing —
    # `rendered`/`failed`/`skipped` are classified from the room's state
    # AFTER the call (FlatPanoramaTasks.render_outcome). `errored` stays a
    # `rescue StandardError` catch-all for what genuinely still escapes the
    # job (e.g. its explicit `raise` when Attached::One#attach silently
    # failed to save) — real enough to keep, rare enough not to conflate with
    # the job's own recorded failures.
    rendered, failed, skipped, errored = [], [], [], []
    candidates.each do |room|
      next if dry_run

      begin
        # See FlatPanoramaTasks.clear_tombstone! — FORCE has to defeat the
        # job's own guards here, before the job ever runs, or a
        # previously-failed (or already-fresh) room stays silently
        # unrenderable no matter how many times this is invoked.
        FlatPanoramaTasks.clear_tombstone!(room) if force

        if inline
          RenderFlatPanoramaJob.perform_now(room.id)
          case FlatPanoramaTasks.render_outcome(room.reload)
          when :rendered then rendered << room
          when :failed   then failed << room
          else                 skipped << room
          end
        else
          RenderFlatPanoramaJob.perform_later(room.id)
          rendered << room # "enqueued" — queued mode can't know the outcome yet
        end
      rescue StandardError => e
        errored << [ room, e ]
      end
    end

    FlatPanoramaTasks.write_report(workspace, rendered: rendered, failed: failed, skipped: skipped,
                                    errored: errored, dry_run: dry_run, inline: inline)

    if inline
      puts "rendered: #{rendered.size}   failed: #{failed.size}   skipped: #{skipped.size}   errored: #{errored.size}"
    else
      puts "enqueued: #{rendered.size}   errored: #{errored.size}"
    end

    # DRY_RUN never calls write_report (it returns before touching disk), so
    # it must not point the operator at report files that were never written
    # — least of all another run's leftover files in the same directory.
    if dry_run
      puts "(dry run — nothing rendered, enqueued, or written)"
    elsif inline
      puts "report: tmp/flat_panoramas/"
    else
      puts "nothing has RUN yet — check `panoramas:flat_status` after the queue drains"
    end
  end

  desc "Count rooms with missing, stale, failed, or orphaned flat panoramas (WORKSPACE=slug)"
  task flat_status: :environment do
    workspace = FlatPanoramaTasks.workspace!
    rooms = FlatPanoramaTasks.scope(workspace).to_a

    stale  = FlatPanoramaTasks.candidates(rooms, force: false)
    # Same predicate `candidates` uses to EXCLUDE a tombstoned room (unless
    # force) — so `stale` and `failed` are disjoint by construction, not by
    # coincidence. A looser check here (e.g. "flat_render_failed_at present?"
    # without matching flat_render_source_key) would double-count a room
    # whose tombstone predates a since-replaced photo.
    failed = rooms.select { |r| FlatPanoramaTasks.tombstoned?(r) }
    # A room with a render and NO panorama — the orphan the lifecycle exists to
    # prevent. Invisible to every other count here, because they all scope to
    # rooms that HAVE a panorama. .distinct for the same reason `scope` below
    # has it: schema.rb's uniqueness index does not prevent two flat_panorama
    # rows with different blobs, which would double-count a room here.
    orphans = Room.where(workspace: workspace)
                  .joins(:flat_panorama_attachment).where.missing(:panorama_attachment)
                  .distinct.count

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

  # LIMIT=abc or LIMIT=0 would otherwise silently become `first(0)` — the run
  # prints a plausible "to render: 0 of 227" and "enqueued: 0" and does
  # nothing, with no error. A typo must not turn a backfill into a silent
  # no-op.
  def parse_limit!(raw)
    return nil if raw.blank?

    limit = Integer(raw, exception: false)
    abort "LIMIT must be a positive integer, got #{raw.inspect}" if limit.nil? || limit < 1
    limit
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

  # source_key is read UNCONDITIONALLY, even on the `next` branches that do
  # not need it, so the eager-loaded panorama_attachment: :blob is always
  # touched. Reading it only on the branch that needs it is correct-looking
  # but wrong: on a fresh backfill (the common case — flat_panorama never
  # attached) not one candidate ever reaches that branch, so Bullet flags the
  # whole `includes(panorama_attachment: :blob)` as unused eager loading for
  # the entire run.
  #
  # Tombstoned rooms are EXCLUDED here (unless force), not just left for the
  # job to skip. RenderFlatPanoramaJob#permanently_failed? guarantees the job
  # never touches them, so counting them as renderable makes `to render` and
  # `missing/stale` both lie — an operator watching a backfill fail to
  # converge across repeated runs gets no signal that it's stuck on
  # tombstones rather than still working through a real backlog.
  #
  # The staleness check's third condition mirrors RenderFlatPanoramaJob#fresh?
  # exactly: a blob whose metadata stamps match but whose FILE is gone (a
  # SIGKILL between the attachment commit and the upload) must count as
  # stale, or it is permanently invisible — attached? lies true, :poster never
  # engages, and the room serves a 404 image forever with nothing in this
  # surface able to see it.
  def candidates(scope, force: false)
    scope.select do |room|
      source_key = room.panorama.blob.key
      next true if force
      next false if tombstoned?(room, source_key)
      next true unless room.flat_panorama.attached?

      blob = room.flat_panorama.blob
      blob.metadata["source_blob_key"] != source_key ||
        blob.metadata["projection"] != Panorama::Rectilinear.signature ||
        !blob.service.exist?(blob.key)
    end
  end

  # Mirrors RenderFlatPanoramaJob#permanently_failed? exactly — the tombstone
  # is keyed on the SOURCE blob so replacing the bad photo clears it (a stamp
  # tied to an old, since-replaced source key does not count).
  def tombstoned?(room, source_key = room.panorama.blob.key)
    meta = room.panorama.blob.metadata
    meta["flat_render_failed_at"].present? && meta["flat_render_source_key"] == source_key
  end

  # Post-condition classification for INLINE mode — see the long comment in
  # the render_flat task for why "perform_now did not raise" cannot be used
  # instead. Mirrors RenderFlatPanoramaJob#fresh? (the RENDERED case) and
  # #permanently_failed? (the FAILED case); anything else — including "source
  # purged mid-render, output discarded" and "still fresh, guard skipped it"
  # — is SKIPPED, not a failure.
  def render_outcome(room)
    flat   = room.flat_panorama
    source = room.panorama

    if flat.attached? && source.attached? &&
       flat.blob.metadata["source_blob_key"] == source.blob.key &&
       flat.blob.metadata["projection"] == Panorama::Rectilinear.signature
      return :rendered
    end

    return :failed if source.attached? && tombstoned?(room, source.blob.key)

    :skipped
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

  def write_report(workspace, rendered:, failed:, skipped:, errored:, dry_run:, inline:)
    return if dry_run

    dir = Rails.root.join("tmp/flat_panoramas")
    FileUtils.mkdir_p(dir)
    stamp = Time.current.strftime("%Y-%m-%d %H:%M %Z")

    if inline
      # Only written in INLINE mode. Queued mode has not run anything yet —
      # unconditionally overwriting flat_failed.txt there would destroy a
      # PRIOR inline run's real failure list with an always-empty one.
      failures = failed.map { |r| [ r.rmrecnbr, r.panorama.blob.metadata["flat_render_error"] ] } +
                 errored.map { |r, e| [ r.rmrecnbr, "#{e.class}: #{e.message} (unexpected — bypassed the job's own failure handling)" ] }

      File.write(dir.join("flat_failed.txt"), <<~HEADER + failures.map { |rmrecnbr, msg| "#{rmrecnbr}\t#{msg}" }.join("\n") + "\n")
        # Flat panorama renders that FAILED in workspace "#{workspace.slug}"
        # #{stamp} — #{failures.size} failures
        # Remedy: replace the room's panorama with the 2:1 mi_locations equirect
        # export, or clear it. Until then the room serves the :poster fallback —
        # degraded (a squashed strip) but not broken.
      HEADER

      File.write(dir.join("flat_skipped.txt"), <<~HEADER + skipped.map(&:rmrecnbr).join("\n") + "\n")
        # Flat panorama renders SKIPPED (already fresh, or superseded mid-render)
        # in workspace "#{workspace.slug}"
        # #{stamp} — #{skipped.size} rooms
      HEADER
    end

    File.write(dir.join("flat_#{inline ? 'rendered' : 'enqueued'}.txt"),
               "# #{inline ? 'RENDERED' : 'ENQUEUED (not yet run)'} in workspace \"#{workspace.slug}\"\n# #{stamp} — #{rendered.size} rooms\n" +
               rendered.map(&:rmrecnbr).join("\n") + "\n")
  end
end
