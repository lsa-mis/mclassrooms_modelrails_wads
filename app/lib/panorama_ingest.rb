# frozen_string_literal: true

# Bulk loader for the room panorama library (lib/tasks/panoramas.rake): a
# directory of "<rmrecnbr>.jpg" files — the mi_locations export — attached
# onto the matching rooms' `panorama` slot within ONE workspace.
#
# Perceived-speed rule: the pano pane's static poster (the :poster named
# variant on Room#panorama) is eagerly processed here, at ingest, so the
# first visitor to a room page gets a ready-made ~1024px webp instead of
# waiting for vips to chew a multi-MB equirectangular JPEG on-request. The
# full-size blob itself stays click-to-load behind Pannellum's opt-in button.
#
# Idempotent and re-runnable: rooms with a panorama already attached are
# skipped (listed in the result) unless `replace: true`. Per-file failures
# (corrupt image, validation reject) land in `errors` without stopping the
# run. `dry_run: true` attaches nothing but reports every list as-if — the
# rooms_without_panorama list treats would-be attaches as covered.
#
# Result lists (the curation report Dave asked for):
#   unmatched_files        — files whose stem matches no room in the workspace
#   rooms_without_panorama — LISTED CLASSROOMS (the user-visible directory)
#                            still lacking a panorama after this run
class PanoramaIngest
  Result = Struct.new(:attached, :replaced, :skipped_existing, :unmatched_files,
                      :rooms_without_panorama, :errors, :dry_run, keyword_init: true)

  IngestFailed = Class.new(StandardError)

  def self.call(directory:, workspace:, replace: false, dry_run: false, progress: nil)
    new(directory:, workspace:, replace:, dry_run:, progress:).call
  end

  def initialize(directory:, workspace:, replace:, dry_run:, progress:)
    @directory = directory
    @workspace = workspace
    @replace   = replace
    @dry_run   = dry_run
    @progress  = progress
  end

  def call
    result = Result.new(attached: [], replaced: [], skipped_existing: [],
                        unmatched_files: [], errors: [], dry_run: @dry_run)
    rooms_by_rmrecnbr = Room.where(workspace: @workspace).index_by { |room| room.rmrecnbr.to_s }
    covered_room_ids  = Set.new

    files.each do |filename|
      room = rooms_by_rmrecnbr[File.basename(filename, ".*")]
      next result.unmatched_files << filename unless room

      if room.panorama.attached? && !@replace
        covered_room_ids << room.id
        result.skipped_existing << filename
        next
      end

      begin
        list = room.panorama.attached? ? result.replaced : result.attached
        attach(room, filename) unless @dry_run
        covered_room_ids << room.id
        list << filename
        @progress&.call(filename)
      rescue StandardError => e
        result.errors << "#{filename}: #{e.class}: #{e.message}"
      end
    end

    result.rooms_without_panorama = Room.where(workspace: @workspace).classroom.listed
      .reject { |room| covered_room_ids.include?(room.id) || room.panorama.attached? }
    result
  end

  private

  def files
    Dir.children(@directory)
       .select { |f| f.downcase.end_with?(".jpg", ".jpeg") }
       .sort
  end

  def attach(room, filename)
    File.open(File.join(@directory, filename)) do |io|
      room.panorama.attach(io: io, filename: filename, content_type: "image/jpeg")
    end
    # attach saves via `save` (not save!) — a validation reject (e.g. the
    # blob sniffs as non-image) fails silently unless surfaced here
    unless room.errors.empty? && room.panorama.attached?
      raise IngestFailed, room.errors.full_messages.join("; ").presence || "attachment did not persist"
    end

    room.panorama.variant(:poster).processed
  end
end
