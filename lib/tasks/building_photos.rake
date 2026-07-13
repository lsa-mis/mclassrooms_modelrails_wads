# Bulk building-photo ingest (see app/lib/building_photo_ingest.rb for the
# tiered name-matching semantics — sibling of panoramas:ingest).
#
#   bin/rails building_photos:ingest DIR=/path/to/buildings
#   bin/rails building_photos:ingest DIR=... WORKSPACE=slug REPLACE=1
#   bin/rails building_photos:ingest DIR=... DRY_RUN=1
#
# WORKSPACE defaults to the shared directory workspace. Writes the curation
# reports to tmp/building_photo_ingest/.
namespace :building_photos do
  desc "Ingest named building photos into Active Storage (DIR=, WORKSPACE=, REPLACE=1, DRY_RUN=1)"
  task ingest: :environment do
    dir = ENV["DIR"]
    abort "DIR=/path/to/building/photos is required" if dir.blank? || !Dir.exist?(dir)

    workspace = ENV["WORKSPACE"].present? ? Workspace.find_by!(slug: ENV["WORKSPACE"]) : TenancyConfig.shared_workspace
    abort "No shared workspace resolved — pass WORKSPACE=<slug>" if workspace.nil?

    dry_run = ENV["DRY_RUN"].present?
    result = BuildingPhotoIngest.call(
      directory: dir, workspace: workspace,
      replace: ENV["REPLACE"].present?, dry_run: dry_run,
      progress: ->(filename) { puts "  + #{filename}" }
    )

    report_dir = Rails.root.join("tmp/building_photo_ingest")
    FileUtils.mkdir_p(report_dir)
    stamp = Time.current.strftime("%Y-%m-%d %H:%M %Z")

    write_report = ->(basename, heading, lines) {
      path = report_dir.join(basename)
      File.write(path, "# #{heading}\n# #{stamp}#{dry_run ? ' (dry run)' : ''} — #{lines.size} entries\n" +
                       lines.join("\n") + "\n")
      path
    }

    unmatched_path = write_report.call("unmatched_files.txt",
      "Building photos with NO matching building in \"#{workspace.slug}\"", result.unmatched_files)
    ambiguous_path = write_report.call("ambiguous_files.txt",
      "Building photos matching MULTIPLE buildings — attach by hand via the edit form", result.ambiguous_files)
    missing_path = write_report.call("buildings_without_photo.txt",
      "Listed buildings with classrooms in \"#{workspace.slug}\" and NO photo (bldrecnbr / name)",
      result.buildings_without_photo.map { |b| [ b.bldrecnbr, b.name ].compact.join("\t") })

    puts <<~SUMMARY

      Building photo ingest#{dry_run ? ' (DRY RUN — nothing attached)' : ''} — workspace "#{workspace.slug}"
        attached:            #{result.attached.size}
        replaced:            #{result.replaced.size}
        skipped (existing):  #{result.skipped_existing.size}
        errors:              #{result.errors.size}
        unmatched files:     #{result.unmatched_files.size}  -> #{unmatched_path}
        ambiguous files:     #{result.ambiguous_files.size}  -> #{ambiguous_path}
        buildings w/o photo: #{result.buildings_without_photo.size}  -> #{missing_path}
    SUMMARY

    result.errors.each { |line| puts "  ERROR #{line}" }
  end
end
