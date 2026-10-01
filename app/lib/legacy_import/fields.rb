# frozen_string_literal: true

module LegacyImport
  # Curated columns written only where blank, plus the hide flag; sync-owned columns are in neither map.
  # Records load one at a time: Bullet raises on an association walked across a multi-row load.
  class Fields
    ROOM_COLUMNS = { "nickname" => :nickname, "ada_seat_count" => :ada_seat_count }.freeze
    BUILDING_COLUMNS = { "nickname" => :nickname, "latitude" => :latitude, "longitude" => :longitude }.freeze

    def self.call(export:, workspace:, actor:, dry_run:) = new(export:, workspace:, actor:, dry_run:).call

    def initialize(export:, workspace:, actor:, dry_run:)
      @export, @workspace, @actor, @dry_run = export, workspace, actor, dry_run
      @tally = Tally.new
      @now = Time.current
    end

    def call
      @export.rows(:rooms).each do |row|
        key = row.fetch("rmrecnbr").to_s
        update(Room.find_by(workspace: @workspace, rmrecnbr: key), row, ROOM_COLUMNS, "Room", key)
      end
      @export.rows(:buildings).each do |row|
        key = row.fetch("bldrecnbr").to_s
        update(Building.find_by(workspace: @workspace, bldrecnbr: key), row, BUILDING_COLUMNS, "Building", key)
      end
      @tally.to_result
    end

    private

    def update(record, row, columns, model, key)
      return @tally.unmatched!("#{model}\t#{key}") if record.nil?

      attributes = columns.each_with_object({}) do |(field, column), attrs|
        attrs[column] = row[field] if row[field].present? && record.public_send(column).blank?
      end
      attributes.merge!(hidden_at: @now, hidden_by: @actor) if hide?(record, row)
      return @tally.count(:skipped) if attributes.empty?

      unless @dry_run
        error = Curate.call(record:, actor: @actor, action: "#{model.downcase}.legacy_imported", attributes:)
        return @tally.error!("#{model}\t#{key}\t#{error}") if error
      end
      @tally.count(:updated)
    end

    def hide?(record, row) = row["visible"] == false && record.in_feed? && record.hidden_at.nil?
  end
end
