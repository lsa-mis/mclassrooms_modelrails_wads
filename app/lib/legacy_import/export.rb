# frozen_string_literal: true

module LegacyImport
  # The export as downloaded from legacy production (media/manifest.json, curated/data/*.ndjson), read as-is.
  class Export
    Missing = Class.new(StandardError)
    # A manifest that is not JSON or lacks "files"; raised before any write.
    Invalid = Class.new(StandardError)
    # A file whose bytes no longer match the checksum the manifest recorded.
    Mismatch = Class.new(StandardError)

    def self.describe(entry)
      entry.values_at("model", "record_id", "record_label", "attachment_name", "path").join("\t")
    end

    def initialize(root)
      @root = Pathname(root).expand_path
      raise Missing, "#{manifest_path} not found" unless manifest_path.file?
      raise Missing, "#{data_dir} not found" unless data_dir.directory?

      entries
    end

    def media(model) = entries.select { |entry| entry.fetch("model") == model }

    def rows(name)
      path = data_dir.join("#{name}.ndjson")
      raise Missing, "#{path} not found" unless path.file?

      path.each_line.filter_map { |line| JSON.parse(line) unless line.strip.empty? }
    end

    def file(relative_path)
      path = @root.join("media", relative_path)
      raise Missing, "#{path} not found" unless path.file?

      path
    end

    private

    def manifest_path = @root.join("media", "manifest.json")
    def data_dir = @root.join("curated", "data")

    def entries
      @entries ||= JSON.parse(manifest_path.read).fetch("files")
    rescue JSON::ParserError, KeyError, TypeError => e
      raise Invalid, "#{manifest_path} is not a valid manifest with a \"files\" list (#{e.class})"
    end
  end
end
