# frozen_string_literal: true

module LegacyImport
  # Where each legacy still lands in a room's gallery. room_image is always
  # shot 1, whatever its filename says. gallery_imageN is shot N + 1, unless
  # the "Image N" in Grace's filename says otherwise. If two files in a room
  # claim the same shot, the filenames can't be trusted for that room, so
  # every file falls back to its slot.
  module GalleryPositions
    SHOT = /Image\s*(\d+)/i
    Placement = Data.define(:position, :entry, :source)

    def self.call(entries)
      by_filename = entries.map do |entry|
        next by_slot(entry) if entry.fetch("attachment_name") == "room_image"

        shot = entry.fetch("filename").to_s[SHOT, 1].to_i
        shot.positive? ? Placement.new(shot, entry, :filename) : by_slot(entry)
      end
      positions = by_filename.map(&:position)
      positions.uniq.size == positions.size ? by_filename : entries.map { |entry| by_slot(entry) }
    end

    def self.by_slot(entry)
      name = entry.fetch("attachment_name")
      Placement.new(name == "room_image" ? 1 : name.delete_prefix("gallery_image").to_i + 1, entry, :slot)
    end
  end
end
