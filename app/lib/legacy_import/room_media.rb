# frozen_string_literal: true

module LegacyImport
  # A room's legacy media in one Curate call, so the room is the unit of rollback and audit.
  # An existing gallery row only ever gets a new image; authored alt, description and subject stay.
  class RoomMedia
    SINGLE_SLOTS = { "room_panorama" => :panorama, "room_layout" => :seating_chart }.freeze
    GALLERY_SLOT = /\A(room_image|gallery_image[1-5])\z/

    def self.call(export:, workspace:, actor:, dry_run:) = new(export:, workspace:, actor:, dry_run:).call

    def initialize(export:, workspace:, actor:, dry_run:)
      @export, @workspace, @actor, @dry_run = export, workspace, actor, dry_run
      @tally = Tally.new
      @from_filename = 0
      @from_slot = 0
    end

    def call
      @export.media("Room").group_by { |entry| entry.fetch("record_id").to_s }.each do |rmrecnbr, entries|
        room = Room.find_by(workspace: @workspace, rmrecnbr:)
        next entries.each { |entry| @tally.unmatched!(Export.describe(entry)) } if room.nil?

        import(room, entries)
      end
      @tally.info_lines << "gallery positions: #{@from_filename} from filenames, #{@from_slot} from slots"
      @tally.to_result
    end

    private

    def import(room, entries)
      writes = single_writes(room, entries) + gallery_writes(room, entries)
      pending = writes.reject { |write| write[:outcome] == :skipped }
      @tally.count(:skipped, writes.size - pending.size)
      return if pending.empty?

      unless @dry_run
        error = Curate.call(record: room, actor: @actor, action: "room.legacy_imported") do
          pending.each { |write| write[:apply].call }
        end
        return @tally.error!("Room\t#{room.rmrecnbr}\t#{error}") if error
      end
      pending.each { |write| write[:outcome] == :replaced ? @tally.replaced!(write[:report]) : @tally.count(:created) }
    end

    def single_writes(room, entries)
      entries.filter_map do |entry|
        slot = SINGLE_SLOTS[entry.fetch("attachment_name")]
        next if slot.nil?

        { outcome: SlotWriter.outcome(SlotWriter.checksum(room.public_send(slot)), entry.fetch("checksum")),
          report: SlotWriter.replaced_line(room, "#{slot}_alt", entry),
          apply: -> { room.public_send("#{slot}=", SlotWriter.attachable(@export, entry)) } }
      end
    end

    def gallery_writes(room, entries)
      assets = MediaAsset.where(owner: room).order(:position, :id).to_a
      current = gallery_checksums(assets)
      by_position = assets.group_by(&:position).transform_values(&:first)
      stills = entries.select { |entry| entry.fetch("attachment_name").match?(GALLERY_SLOT) }

      GalleryPositions.call(stills).map do |placement|
        placement.source == :filename ? @from_filename += 1 : @from_slot += 1
        asset = by_position[placement.position]
        { outcome: SlotWriter.outcome(asset && current[asset.id], placement.entry.fetch("checksum")),
          report: asset && SlotWriter.replaced_line(asset, "image_alt", placement.entry),
          apply: -> { write_still(room, asset, placement) } }
      end
    end

    # One pluck instead of asset.image per row: Bullet raises on an attachment
    # association walked across the multi-row gallery load.
    def gallery_checksums(assets)
      ActiveStorage::Attachment.where(record_type: "MediaAsset", record_id: assets.map(&:id), name: "image")
                               .joins(:blob).pluck(:record_id, "active_storage_blobs.checksum").to_h
    end

    # Re-found by id for the same reason: replacing the image reads the old
    # attachment, which on a row from the multi-row load is an N+1 to Bullet.
    def write_still(room, asset, placement)
      target = asset ? MediaAsset.find(asset.id) : MediaAsset.new(owner: room, workspace: room.workspace, position: placement.position)
      target.image = SlotWriter.attachable(@export, placement.entry)
      target.save!
    end
  end
end
