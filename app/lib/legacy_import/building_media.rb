# frozen_string_literal: true

module LegacyImport
  # building_image -> Building.photo and floor_plan -> Floor.plan. The export
  # carries only the legacy floor's own id, so a floor matches by exact
  # building name plus normalized label; floors are never created — the sync
  # owns them.
  class BuildingMedia
    FLOOR_RECORD_LABEL = /\A(?<building>.+) floor (?<floor>\S+)\z/

    def self.call(export:, workspace:, actor:, dry_run:) = new(export:, workspace:, actor:, dry_run:).call

    def initialize(export:, workspace:, actor:, dry_run:)
      @export, @workspace, @actor, @dry_run = export, workspace, actor, dry_run
      @tally = Tally.new
    end

    def call
      @export.media("Building").each do |entry|
        building = Building.find_by(workspace: @workspace, bldrecnbr: entry.fetch("record_id").to_s)
        next @tally.unmatched!(Export.describe(entry)) if building.nil?

        write(building, :photo, entry, action: "building.legacy_imported")
      end
      @export.media("Floor").each do |entry|
        floor = find_floor(entry)
        write(floor, :plan, entry, action: "floor.legacy_imported") if floor
      end
      @tally.to_result
    end

    private

    def find_floor(entry)
      match = FLOOR_RECORD_LABEL.match(entry.fetch("record_label").to_s)
      buildings = match ? Building.where(workspace: @workspace, name: match[:building]).to_a : []
      if buildings.size > 1
        @tally.unmatched!("#{Export.describe(entry)}\tambiguous building name")
        return
      end

      floor = buildings.first && buildings.first.floors.find_by(label: FloorLabel.normalize(match[:floor]))
      @tally.unmatched!(Export.describe(entry)) if floor.nil?
      floor
    end

    def write(record, slot, entry, action:)
      outcome = SlotWriter.outcome(SlotWriter.checksum(record.public_send(slot)), entry.fetch("checksum"))
      return @tally.count(:skipped) if outcome == :skipped

      unless @dry_run
        error = Curate.call(record:, actor: @actor, action:) do |r|
          r.public_send("#{slot}=", SlotWriter.attachable(@export, entry))
        end
        return @tally.error!("#{Export.describe(entry)}\t#{error}") if error
      end
      if outcome == :replaced
        @tally.replaced!(SlotWriter.replaced_line(record, "#{slot}_alt", entry))
      else
        @tally.count(:created)
      end
    end
  end
end
