# frozen_string_literal: true

# Writes an export in mi_classrooms' 2026-09-30 shape into a tmpdir, with checksums computed
# from the fixture bytes, so each spec builds only the rows it needs.
module LegacyExportBuilder
  class Tree
    DATA_FILES = %w[rooms buildings notes announcements users].freeze

    def initialize(root)
      @root = Pathname(root)
      @files = []
      @rows = Hash.new { |hash, key| hash[key] = [] }
    end

    def media(model:, record_id:, attachment_name:, fixture:, record_label: "record #{record_id}",
              filename: File.basename(fixture))
      source = Rails.root.join("spec/fixtures/files", fixture)
      path = File.join(model.underscore, record_id.to_s, attachment_name, filename)
      destination = @root.join("media", path)
      FileUtils.mkdir_p(destination.dirname)
      FileUtils.cp(source, destination)
      @files << {
        "model" => model, "record_id" => record_id, "record_label" => record_label,
        "attachment_name" => attachment_name, "filename" => filename,
        "content_type" => Marcel::MimeType.for(source, name: filename),
        "byte_size" => File.size(source),
        "checksum" => Digest::MD5.base64digest(File.binread(source)), "path" => path
      }
      self
    end

    def row(name, attrs)
      @rows[name.to_s] << attrs.stringify_keys
      self
    end

    def remove(relative_path)
      @root.join(relative_path).delete
      self
    end

    def write!
      FileUtils.mkdir_p(@root.join("curated/data"))
      FileUtils.mkdir_p(@root.join("media"))
      @root.join("media/manifest.json").write(JSON.generate("files" => @files))
      DATA_FILES.each do |name|
        @root.join("curated/data/#{name}.ndjson").write(@rows[name].map { |row| "#{row.to_json}\n" }.join)
      end
      @root
    end
  end
end

RSpec.shared_context "legacy export" do
  around do |example|
    Dir.mktmpdir("legacy-export") do |dir|
      @legacy_export_root = dir
      example.run
    end
  end

  let(:export_tree) { LegacyExportBuilder::Tree.new(@legacy_export_root) }

  def legacy_export = LegacyImport::Export.new(export_tree.write!)

  # The importer under test against the example's export; each spec supplies workspace and actor.
  def run_importer(dry_run: false, actor: self.actor)
    described_class.call(export: legacy_export, workspace:, actor:, dry_run:)
  end
end
