require "rails_helper"

# Bulk building-photo loader: a directory of human-NAMED files
# ("Mason_Hall.jpg", "Chemistry.jpg" — the mi_locations export) attached onto
# matching buildings' `photo` slot. Unlike PanoramaIngest's exact rmrecnbr
# join, matching is TIERED: case-insensitive exact name first, then a UNIQUE
# Building.search_name (FTS) hit; multiple hits are refused into an
# `ambiguous_files` list rather than guessed — a wrong building photo is
# worse than a missing one. The :hero and :thumb variants are eagerly
# processed so the building page never serves a raw multi-MB original.
RSpec.describe BuildingPhotoIngest do
  let!(:workspace) { create(:workspace, slug: "bldg-photo-ws", personal: false) }
  let!(:mason)     { building_with_classroom("MASON HALL", "1200") }
  let!(:chem)      { building_with_classroom("CHEMISTRY AND DOW WILLARD H LABORATORY", "1300") }
  let!(:bare)      { building_with_classroom("WEST HALL", "2000") }

  def building_with_classroom(name, number)
    create(:building, name: name, workspace: workspace).tap do |b|
      create(:room, building: b, workspace: workspace, room_number: number, room_type: "Classroom",
             facility_code: "#{name[0, 3]}#{number}", instructional_seat_count: 30)
    end
  end

  around do |example|
    Dir.mktmpdir("bldg-photos") do |dir|
      @dir = dir
      example.run
    end
  end

  def add_photo(filename)
    FileUtils.cp(file_fixture("room.jpg"), File.join(@dir, filename))
  end

  def call(**opts)
    described_class.call(directory: @dir, workspace: workspace, **opts)
  end

  it "attaches on a case-insensitive exact name match and eagerly processes variants" do
    add_photo("Mason_Hall.jpg")

    result = call

    expect(mason.reload.photo).to be_attached
    # :hero + :thumb pre-processed — VariantRecords prove vips already ran
    expect(ActiveStorage::VariantRecord.where(blob_id: mason.photo.blob.id).count).to eq(2)
    expect(result.attached).to contain_exactly("Mason_Hall.jpg")
  end

  it "falls back to a UNIQUE search-index hit for partial names" do
    add_photo("Chemistry.jpg")

    result = call

    expect(chem.reload.photo).to be_attached
    expect(result.attached).to contain_exactly("Chemistry.jpg")
  end

  it "refuses ambiguous matches into their own list instead of guessing" do
    add_photo("Hall.jpg") # search matches MASON HALL and WEST HALL (and more)

    result = call

    expect(result.ambiguous_files).to contain_exactly("Hall.jpg")
    expect(Building.where(workspace: workspace).none? { |b| b.photo.attached? }).to be(true)
  end

  it "cleans stems (underscores, trailing dots) and lists unmatched files and photo-less buildings" do
    add_photo("Mason_Hall..jpg") # trailing dot before extension, like Kraus_Natural_Science_Bldg..jpg
    add_photo("Ruthven_Exhibit_Museum.jpg")

    result = call

    expect(mason.reload.photo).to be_attached
    expect(result.unmatched_files).to contain_exactly("Ruthven_Exhibit_Museum.jpg")
    expect(result.buildings_without_photo).to contain_exactly(chem, bare)
  end

  it "skips already-attached buildings unless replace:" do
    add_photo("Mason_Hall.jpg")
    call
    original_blob = mason.reload.photo.blob

    expect(call.skipped_existing).to contain_exactly("Mason_Hall.jpg")
    expect(mason.reload.photo.blob).to eq(original_blob)

    expect(call(replace: true).replaced).to contain_exactly("Mason_Hall.jpg")
    expect(mason.reload.photo.blob).not_to eq(original_blob)
  end

  it "attaches nothing on dry_run but reports every list as-if" do
    add_photo("Mason_Hall.jpg")

    result = call(dry_run: true)

    expect(mason.reload.photo).not_to be_attached
    expect(result.attached).to contain_exactly("Mason_Hall.jpg")
    expect(result.buildings_without_photo).to contain_exactly(chem, bare)
  end

  it "isolates per-file failures and keeps going" do
    add_photo("Mason_Hall.jpg")
    add_photo("West_Hall.jpg")
    File.write(File.join(@dir, "Mason_Hall.jpg"), "not a jpeg")

    result = call

    expect(result.errors.size).to eq(1)
    expect(result.errors.first).to include("Mason_Hall.jpg")
    expect(bare.reload.photo).to be_attached
  end

  it "never matches buildings in another workspace" do
    other_ws = create(:workspace, slug: "bldg-other-ws", personal: false)
    foreign = create(:building, name: "TAPPAN HALL", workspace: other_ws)
    add_photo("Tappan_Hall.jpg")

    result = call

    expect(foreign.reload.photo).not_to be_attached
    expect(result.unmatched_files).to contain_exactly("Tappan_Hall.jpg")
  end
end
