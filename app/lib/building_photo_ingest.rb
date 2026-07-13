# frozen_string_literal: true

# Bulk loader for building photos (lib/tasks/building_photos.rake): a
# directory of human-NAMED files — "Mason_Hall.jpg", "Chemistry.jpg", the
# mi_locations export — attached onto matching buildings' `photo` slot
# within ONE workspace.
#
# Matching is TIERED, unlike PanoramaIngest's exact rmrecnbr join (these
# files carry display names, not record numbers):
#   1. case-insensitive exact `name` match on the cleaned stem
#      (underscores -> spaces, trailing dots stripped)
#   2. a UNIQUE Building.search_name (FTS) hit — "Chemistry" finds
#      "CHEMISTRY AND DOW WILLARD H LABORATORY"
#   Multiple FTS hits are REFUSED into `ambiguous_files` rather than guessed
#   — a wrong building photo is worse than a missing one; attach those by
#   hand through the building edit form.
#
# Perceived speed: the :hero (building page) and :thumb (edit form) named
# variants are eagerly processed at ingest so no visitor ever waits on a
# multi-MB original being transformed on request.
#
# Same operational contract as PanoramaIngest: idempotent (skip attached
# unless replace:), per-file failures collect into `errors`, dry_run reports
# as-if. `buildings_without_photo` covers LISTED buildings WITH classrooms —
# the ones the directory actually shows.
class BuildingPhotoIngest
  Result = Struct.new(:attached, :replaced, :skipped_existing, :unmatched_files,
                      :ambiguous_files, :buildings_without_photo, :errors, :dry_run,
                      keyword_init: true)

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
    result = Result.new(attached: [], replaced: [], skipped_existing: [], unmatched_files: [],
                        ambiguous_files: [], errors: [], dry_run: @dry_run)
    covered_ids = Set.new

    files.each do |filename|
      building, ambiguous = match(stem(filename))
      next result.ambiguous_files << filename if ambiguous
      next result.unmatched_files << filename unless building

      if building.photo.attached? && !@replace
        covered_ids << building.id
        result.skipped_existing << filename
        next
      end

      begin
        list = building.photo.attached? ? result.replaced : result.attached
        attach(building, filename) unless @dry_run
        covered_ids << building.id
        list << filename
        @progress&.call(filename)
      rescue StandardError => e
        result.errors << "#{filename}: #{e.class}: #{e.message}"
      end
    end

    result.buildings_without_photo = Building.where(workspace: @workspace).listed.with_classrooms
      .reject { |building| covered_ids.include?(building.id) || building.photo.attached? }
    result
  end

  private

  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze

  def files
    Dir.children(@directory)
       .select { |f| IMAGE_EXTENSIONS.include?(File.extname(f).downcase) }
       .sort
  end

  # "Kraus_Natural_Science_Bldg..jpg" -> "Kraus Natural Science Bldg"
  def stem(filename)
    File.basename(filename, ".*").tr("_", " ").sub(/[. ]+\z/, "").strip
  end

  # -> [building, ambiguous?]
  def match(stem)
    scope = Building.where(workspace: @workspace)
    exact = scope.where("LOWER(name) = ?", stem.downcase).first
    return [ exact, false ] if exact

    hits = Building.search_name(stem).where(workspace: @workspace).limit(2).to_a
    return [ nil, true ] if hits.size > 1

    [ hits.first, false ]
  end

  def attach(building, filename)
    File.open(File.join(@directory, filename)) do |io|
      building.photo.attach(io: io, filename: filename,
                            content_type: Marcel::MimeType.for(extension: File.extname(filename)))
    end
    unless building.errors.empty? && building.photo.attached?
      raise IngestFailed, building.errors.full_messages.join("; ").presence || "attachment did not persist"
    end

    building.photo.variant(:hero).processed
    building.photo.variant(:thumb).processed
  end
end
