# Bulk panorama ingest (see app/lib/panorama_ingest.rb for the semantics).
#
#   bin/rails panoramas:ingest DIR=/path/to/ALL_PANOS
#   bin/rails panoramas:ingest DIR=... WORKSPACE=mclassrooms REPLACE=1
#   bin/rails panoramas:ingest DIR=... DRY_RUN=1
#
# WORKSPACE defaults to the shared directory workspace. Writes the two
# curation reports to tmp/panorama_ingest/.
namespace :panoramas do
  desc "Ingest <rmrecnbr>.jpg panoramas into Active Storage (DIR=, WORKSPACE=, REPLACE=1, DRY_RUN=1)"
  task ingest: :environment do
    dir = ENV["DIR"]
    abort "DIR=/path/to/panoramas is required" if dir.blank? || !Dir.exist?(dir)

    workspace = ENV["WORKSPACE"].present? ? Workspace.find_by!(slug: ENV["WORKSPACE"]) : TenancyConfig.shared_workspace
    abort "No shared workspace resolved — pass WORKSPACE=<slug>" if workspace.nil?

    dry_run = ENV["DRY_RUN"].present?
    done = 0
    result = PanoramaIngest.call(
      directory: dir, workspace: workspace,
      replace: ENV["REPLACE"].present?, dry_run: dry_run,
      progress: ->(filename) {
        done += 1
        puts "  [#{done}] #{filename}" if (done % 25).zero?
      }
    )

    report_dir = Rails.root.join("tmp/panorama_ingest")
    FileUtils.mkdir_p(report_dir)
    stamp = Time.current.strftime("%Y-%m-%d %H:%M %Z")

    unmatched_path = report_dir.join("unmatched_files.txt")
    File.write(unmatched_path, <<~HEADER + result.unmatched_files.join("\n") + "\n")
      # Panorama files with NO matching room in workspace "#{workspace.slug}" (by rmrecnbr)
      # #{stamp}#{dry_run ? ' (dry run)' : ''} — #{result.unmatched_files.size} files
    HEADER

    missing_path = report_dir.join("rooms_without_panorama.txt")
    room_lines = result.rooms_without_panorama.map do |room|
      [ room.rmrecnbr, room.facility_code, room.display_name ].compact.join("\t")
    end
    File.write(missing_path, <<~HEADER + room_lines.join("\n") + "\n")
      # Listed classrooms in "#{workspace.slug}" with NO panorama#{dry_run ? ' (as-if, dry run)' : ''}
      # #{stamp} — #{result.rooms_without_panorama.size} rooms  (rmrecnbr / facility code / name)
    HEADER

    puts <<~SUMMARY

      Panorama ingest#{dry_run ? ' (DRY RUN — nothing attached)' : ''} — workspace "#{workspace.slug}"
        attached:            #{result.attached.size}
        replaced:            #{result.replaced.size}
        skipped (existing):  #{result.skipped_existing.size}
        errors:              #{result.errors.size}
        unmatched files:     #{result.unmatched_files.size}  -> #{unmatched_path}
        rooms w/o panorama:  #{result.rooms_without_panorama.size}  -> #{missing_path}
    SUMMARY

    result.errors.each { |line| puts "  ERROR #{line}" }
  end
end
