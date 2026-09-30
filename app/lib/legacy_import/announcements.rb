# app/lib/legacy_import/announcements.rb
# frozen_string_literal: true

module LegacyImport
  # Page announcements. An empty legacy body is skipped, and a page that
  # already has an announcement keeps it — copy written here wins over copy
  # written in the old app.
  class Announcements
    def self.call(export:, workspace:, actor:, dry_run:) = new(export:, workspace:, dry_run:).call

    def initialize(export:, workspace:, dry_run:)
      @export, @workspace, @dry_run = export, workspace, dry_run
      @tally = Tally.new
    end

    def call
      @export.rows(:announcements).each do |row|
        slot = row.fetch("slot")
        next @tally.unmatched!("Announcement\t#{slot}") unless Announcement.slots.key?(slot)
        next @tally.count(:skipped) if row["body_html"].blank? || Announcement.exists?(slot:)

        Announcement.create!(workspace: @workspace, slot:, body: row["body_html"]) unless @dry_run
        @tally.count(:created)
      rescue ActiveRecord::RecordInvalid => e
        @tally.error!("Announcement\t#{slot}\t#{e.message}")
      end
      @tally.to_result
    end
  end
end
