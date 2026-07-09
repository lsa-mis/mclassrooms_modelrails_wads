require "rails_helper"

RSpec.describe BulkUpload::Matcher do
  # Any object responding to #filename works — the matcher only ever reads
  # `blob.filename.to_s`. A bare Struct keeps these examples free of
  # ActiveStorage attachment setup.
  UploadBlob = Struct.new(:filename)

  let(:workspace) { create(:workspace) }
  let(:building)  { create(:building, workspace: workspace) }
  let!(:room)     { create(:room, workspace: workspace, building: building, facility_code: "MLB1200") }

  # Room is Tenanted (belongs_to :workspace, `for_current_workspace` scope) —
  # set the shared-workspace tenancy context the way other lib specs do
  # (spec/lib/characteristic_filter_groups_spec.rb), even though
  # Room.find_by_facility_code itself queries by the normalized column
  # directly rather than through `for_current_workspace`.
  before { Current.workspace = workspace }

  def blob(filename) = UploadBlob.new(filename)

  it "matches a bare image filename to :photo" do
    report = described_class.call([ blob("MLB1200.jpg") ])

    expect(report.unmatched).to be_empty
    match = report.matched.first
    expect(match.blob.filename).to eq("MLB1200.jpg")
    expect(match.room).to eq(room)
    expect(match.slot).to eq(:photo)
  end

  it "matches a lowercase filename case-insensitively and resolves the room via normalized lookup" do
    report = described_class.call([ blob("mlb1200.JPG") ])

    expect(report.unmatched).to be_empty
    match = report.matched.first
    expect(match.room).to eq(room)
    expect(match.slot).to eq(:photo)
  end

  it "matches a _pano suffix to :panorama" do
    report = described_class.call([ blob("MLB1200_pano.webp") ])

    match = report.matched.first
    expect(match.room).to eq(room)
    expect(match.slot).to eq(:panorama)
  end

  it "matches a _chairs.pdf suffix to :seating_chart" do
    report = described_class.call([ blob("MLB1200_chairs.pdf") ])

    match = report.matched.first
    expect(match.room).to eq(room)
    expect(match.slot).to eq(:seating_chart)
  end

  it "matches a _chairs.png suffix to :seating_chart" do
    report = described_class.call([ blob("MLB1200_chairs.png") ])

    match = report.matched.first
    expect(match.room).to eq(room)
    expect(match.slot).to eq(:seating_chart)
  end

  it "reports an unrecognized extension as :unrecognized_filename" do
    report = described_class.call([ blob("notes.txt") ])

    expect(report.matched).to be_empty
    unmatched = report.unmatched.first
    expect(unmatched.blob.filename).to eq("notes.txt")
    expect(unmatched.reason).to eq(:unrecognized_filename)
  end

  it "reports a recognized filename with no matching room as :room_not_found" do
    report = described_class.call([ blob("ZZZ9999.jpg") ])

    expect(report.matched).to be_empty
    unmatched = report.unmatched.first
    expect(unmatched.blob.filename).to eq("ZZZ9999.jpg")
    expect(unmatched.reason).to eq(:room_not_found)
  end

  it "lets the _pano suffix win over the bare-photo pattern (pattern precedence)" do
    report = described_class.call([ blob("MLB1200_pano.jpg") ])

    match = report.matched.first
    expect(match.slot).to eq(:panorama)
    expect(match.slot).not_to eq(:photo)
  end

  it "sorts a mixed batch into matched and unmatched buckets" do
    report = described_class.call([
      blob("MLB1200.jpg"),
      blob("MLB1200_pano.webp"),
      blob("notes.txt"),
      blob("ZZZ9999.jpg")
    ])

    expect(report.matched.map(&:slot)).to contain_exactly(:photo, :panorama)
    expect(report.unmatched.map(&:reason)).to contain_exactly(:unrecognized_filename, :room_not_found)
  end
end
