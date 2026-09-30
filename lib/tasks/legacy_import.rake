# frozen_string_literal: true

# One-time carry-over of mi_classrooms' hand-curated content. Design:
# planning/specs/2026-09-30-mclassrooms-legacy-import-design.md.
#
#   bin/rails legacy:import EXPORT=~/mclassrooms-export WORKSPACE=mclassrooms
#   bin/rails legacy:import EXPORT=... WORKSPACE=... DRY_RUN=1
#   bin/rails legacy:import EXPORT=... WORKSPACE=... ONLY=media,notes
#
# Reports land in tmp/legacy_import/<timestamp>/ unless REPORT_DIR is set.
namespace :legacy do
  desc "Import the mi_classrooms export (EXPORT=, WORKSPACE=, DRY_RUN=1, ONLY=fields,media,announcements,notes, REPORT_DIR=)"
  task import: :environment do
    export = ENV["EXPORT"].presence
    abort "EXPORT=/path/to/mclassrooms-export is required" if export.nil?
    slug = ENV["WORKSPACE"].presence
    abort "WORKSPACE=<slug> is required" if slug.nil?
    workspace = Workspace.kept.find_by(slug:)
    abort "No kept workspace found for WORKSPACE=#{slug.inspect}" if workspace.nil?
    dry_run = ENV["DRY_RUN"].present?
    only = ENV["ONLY"].to_s.split(",").map(&:strip).reject(&:empty?)

    result = LegacyImport::Runner.call(export_path: File.expand_path(export), workspace:, dry_run:, only:)
    report_dir = ENV["REPORT_DIR"].presence ||
                 Rails.root.join("tmp/legacy_import", Time.current.strftime("%Y%m%d-%H%M%S")).to_s
    LegacyImport::Report.write(result, dir: report_dir)

    puts "Legacy import#{' (DRY RUN — nothing written)' if dry_run} — workspace \"#{slug}\""
    puts LegacyImport::Report.table(result)
    puts "report: #{report_dir}"
    abort "legacy:import failed: #{result.errors.join('; ')}" unless result.success?
  end
end
