# frozen_string_literal: true

module LegacyImport
  # Legacy notes and alerts under the Legacy import account, with an attribution line. Two passes so
  # a reply finds its imported parent; broadcasts are suppressed, since nobody is subscribed.
  class Notes
    def self.call(export:, workspace:, actor:, dry_run:) = new(export:, workspace:, actor:, dry_run:).call

    def initialize(export:, workspace:, actor:, dry_run:)
      @export, @workspace, @actor, @dry_run = export, workspace, actor, dry_run
      @tally = Tally.new
    end

    def call
      roots, replies = @export.rows(:notes).partition { |row| row["parent_legacy_id"].nil? }
      imported = {}
      Note.suppressing_turbo_broadcasts do
        roots.each { |row| import(row, parent: nil, imported:) }
        replies.each do |row|
          parent = imported[row["parent_legacy_id"]]
          next @tally.unmatched!("Note\t#{row["legacy_id"]}\tparent #{row["parent_legacy_id"]} not imported") if parent.nil?

          import(row, parent:, imported:)
        end
      end
      @tally.to_result
    end

    private

    def import(row, parent:, imported:)
      notable = find_notable(row)
      return @tally.unmatched!("Note\t#{row["legacy_id"]}\t#{row["notable_type"]} #{row["notable_key"]}") if notable.nil?

      created_at = Time.iso8601(row.fetch("created_at"))
      existing = @actor.persisted? && Note.find_by(notable:, author: @actor, created_at:)
      if existing
        imported[row["legacy_id"]] = existing
        return @tally.count(:skipped)
      end

      imported[row["legacy_id"]] = @dry_run ? :dry_run : create(row, notable:, parent:, created_at:)
      @tally.count(:created)
    rescue ActiveRecord::RecordInvalid => e
      @tally.error!("Note\t#{row["legacy_id"]}\t#{e.message}")
    end

    def create(row, notable:, parent:, created_at:)
      updated_at = Time.iso8601(row["updated_at"] || row.fetch("created_at"))
      note = Note.create!(workspace: @workspace, notable:, author: @actor, parent:, alert: row["alert"] == true,
                          body: body_html(row, created_at), created_at:, updated_at:)
      # Saving the rich-text body touches the note; put the legacy value back.
      note.update_column(:updated_at, updated_at)
      note
    end

    def find_notable(row)
      key = row.fetch("notable_key").to_s
      case row["notable_type"]
      when "Room" then Room.find_by(workspace: @workspace, rmrecnbr: key)
      when "Building" then Building.find_by(workspace: @workspace, bldrecnbr: key)
      end
    end

    def body_html(row, created_at)
      author = ERB::Util.html_escape(row["author_email"].presence || "an unknown author")
      "#{row["body_html"]}<p><em>Originally posted by #{author} on #{created_at.strftime("%b %-d, %Y")}.</em></p>"
    end
  end
end
