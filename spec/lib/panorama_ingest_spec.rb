require "rails_helper"

# Bulk panorama loader: a directory of "<rmrecnbr>.jpg" files (the
# mi_locations panorama library) attached onto matching rooms' `panorama`
# slot, with the :poster variant eagerly processed so the first visitor
# never pays the vips transform. Idempotent: already-attached rooms are
# skipped unless replace:. The Result carries the two curation lists Dave
# asked for — files with no room in our system, and listed classrooms with
# no panorama.
RSpec.describe PanoramaIngest do
  include ClassroomBuilders

  let!(:workspace) { create(:workspace, slug: "pano-ingest-ws", personal: false) }
  let!(:building)  { create(:building, name: "Mason Hall", workspace: workspace) }
  let!(:covered)   { classroom(building, "1200", 80) }
  let!(:bare)      { classroom(building, "2330", 20) }

  around do |example|
    Dir.mktmpdir("panos") do |dir|
      @dir = dir
      example.run
    end
  end

  def add_pano(stem)
    FileUtils.cp(file_fixture("room.jpg"), File.join(@dir, "#{stem}.jpg"))
  end

  def call(**opts)
    described_class.call(directory: @dir, workspace: workspace, **opts)
  end

  it "attaches matching files by rmrecnbr and eagerly processes the poster variant" do
    add_pano(covered.rmrecnbr)

    result = call

    expect(covered.reload.panorama).to be_attached
    expect(covered.panorama.filename.to_s).to eq("#{covered.rmrecnbr}.jpg")
    # the poster (pano pane's static preview) is pre-processed at ingest —
    # a VariantRecord for the blob proves vips already ran
    expect(ActiveStorage::VariantRecord.where(blob_id: covered.panorama.blob.id)).to exist
    expect(result.attached).to contain_exactly("#{covered.rmrecnbr}.jpg")
  end

  it "reports files with no matching room and listed rooms with no panorama" do
    add_pano(covered.rmrecnbr)
    add_pano("9999999") # no such room

    result = call

    expect(result.unmatched_files).to contain_exactly("9999999.jpg")
    expect(result.rooms_without_panorama).to contain_exactly(bare)
  end

  it "skips already-attached rooms unless replace:, then replaces" do
    add_pano(covered.rmrecnbr)
    call
    original_blob = covered.reload.panorama.blob

    result = call
    expect(result.skipped_existing).to contain_exactly("#{covered.rmrecnbr}.jpg")
    expect(covered.reload.panorama.blob).to eq(original_blob)

    result = call(replace: true)
    expect(result.replaced).to contain_exactly("#{covered.rmrecnbr}.jpg")
    expect(covered.reload.panorama.blob).not_to eq(original_blob)
  end

  it "attaches nothing on dry_run but still reports both lists as-if" do
    add_pano(covered.rmrecnbr)
    add_pano("9999999")

    result = call(dry_run: true)

    expect(covered.reload.panorama).not_to be_attached
    expect(result.attached).to contain_exactly("#{covered.rmrecnbr}.jpg")
    expect(result.unmatched_files).to contain_exactly("9999999.jpg")
    # covered WOULD be covered — only the file-less room is reported
    expect(result.rooms_without_panorama).to contain_exactly(bare)
  end

  it "isolates per-file failures into errors and keeps going" do
    add_pano(covered.rmrecnbr)
    add_pano(bare.rmrecnbr)
    # corrupt one file so attach/variant processing raises for it alone
    File.write(File.join(@dir, "#{covered.rmrecnbr}.jpg"), "not a jpeg")

    result = call

    expect(result.errors.size).to eq(1)
    expect(result.errors.first).to include(covered.rmrecnbr)
    expect(bare.reload.panorama).to be_attached
  end

  it "never touches rooms in another workspace" do
    other_ws = create(:workspace, slug: "pano-other-ws", personal: false)
    other_building = create(:building, name: "Angell Hall", workspace: other_ws)
    foreign = classroom(other_building, "3000", 300)
    add_pano(foreign.rmrecnbr)

    result = call

    expect(foreign.reload.panorama).not_to be_attached
    expect(result.unmatched_files).to contain_exactly("#{foreign.rmrecnbr}.jpg")
  end
end
