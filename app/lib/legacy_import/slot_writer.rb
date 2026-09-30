# frozen_string_literal: true

module LegacyImport
  # Legacy wins for a single-slot image: attach when empty, skip when
  # byte-identical, replace otherwise. Both apps store Active Storage's base64
  # MD5, so checksums compare directly.
  module SlotWriter
    def self.outcome(current_checksum, legacy_checksum)
      return :created if current_checksum.nil?

      current_checksum == legacy_checksum ? :skipped : :replaced
    end

    def self.checksum(attachment) = attachment.attached? ? attachment.blob.checksum : nil

    # Assign-only; the caller's Curate block saves once, inside its transaction.
    def self.attachable(export, entry)
      path = export.file(entry.fetch("path"))
      bytes = path.binread
      raise Export::Mismatch, "#{path} does not match the manifest checksum" unless Digest::MD5.base64digest(bytes) == entry.fetch("checksum")

      { io: StringIO.new(bytes),
        filename: entry.fetch("filename"), content_type: entry.fetch("content_type") }
    end

    def self.replaced_line(record, alt_column, entry)
      flag = record.read_attribute(alt_column).present? ? "\tAUTHORED ALT — review" : ""
      "#{Export.describe(entry)}#{flag}"
    end
  end
end
