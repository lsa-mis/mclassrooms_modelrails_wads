# frozen_string_literal: true

# Runs a media ingest (building photos, panoramas) over the example's scratch directory.
module MediaIngestHelpers
  def run_ingest(**opts)
    described_class.call(directory: @dir, workspace: workspace, **opts)
  end
end

RSpec.configure do |config|
  config.include MediaIngestHelpers, file_path: %r{spec/lib/(building_photo|panorama)_ingest_spec\.rb}
end
