# frozen_string_literal: true

module BulkUpload
  # Phase 4 Task 10 (Brief §6.3): matches uploaded blobs to rooms + media
  # slots by facility-code filename convention, so the bulk-upload flow can
  # sort a batch of dropped files (photos, panoramas, seating charts) without
  # the uploader hand-picking a room/slot per file. Pure — no I/O beyond the
  # `Room.for_current_workspace.find_by_facility_code` lookup (workspace-
  # scoped defensively, like every other Room lookup, even though D1 never
  # exercises cross-workspace facility codes today); callers own persistence
  # of the match.
  class Matcher
    Match = Data.define(:blob, :room, :slot)
    Unmatched = Data.define(:blob, :reason)
    Report = Data.define(:matched, :unmatched)

    # Order matters: suffixed patterns must win before the bare-photo pattern.
    PATTERNS = [
      [ /\A(?<code>[A-Za-z0-9]+)_pano\.(jpe?g|png|webp)\z/i,        :panorama ],
      [ /\A(?<code>[A-Za-z0-9]+)_chairs\.(pdf|jpe?g|png|webp)\z/i,  :seating_chart ],
      [ /\A(?<code>[A-Za-z0-9]+)\.(jpe?g|png|webp)\z/i,             :photo ]
    ].freeze

    def self.call(blobs) = new(blobs).call

    def initialize(blobs)
      @blobs = blobs
    end

    def call
      matched, unmatched = [], []
      @blobs.each do |blob|
        slot, code = slot_for(blob.filename.to_s)
        if slot.nil?
          unmatched << Unmatched.new(blob:, reason: :unrecognized_filename)
        elsif (room = Room.for_current_workspace.find_by_facility_code(code)).nil?
          unmatched << Unmatched.new(blob:, reason: :room_not_found)
        else
          matched << Match.new(blob:, room:, slot:)
        end
      end
      Report.new(matched:, unmatched:)
    end

    private

    def slot_for(filename)
      PATTERNS.each do |pattern, slot|
        m = pattern.match(filename)
        return [ slot, m[:code] ] if m
      end
      nil
    end
  end
end
