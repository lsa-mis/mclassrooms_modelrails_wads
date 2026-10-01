# frozen_string_literal: true

module LegacyImport
  # room_image is shot 1; gallery_imageN is shot N + 1 unless Grace's "Image N" says otherwise.
  # A room whose filenames claim the same shot twice falls back to slot order (see PR #90).
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
