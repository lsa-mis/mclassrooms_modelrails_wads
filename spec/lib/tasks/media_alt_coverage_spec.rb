require "rails_helper"
require "rake"

RSpec.describe "Media::AltCoverage" do
  before(:all) do
    RakeTasks.load_once
  end

  it "counts needs_review vs attached per model/slot" do
    create(:media_asset, image_alt: nil, image_derived_ok: false) # needs_review
    create(:media_asset, image_alt: "authored")                    # authored
    create(:media_asset, image_alt: nil, image_derived_ok: true)

    rows = Media::AltCoverage.report
    gallery = rows.find { |r| r[:model] == "MediaAsset" && r[:slot] == :image }
    expect(gallery[:attached]).to eq(3)
    expect(gallery[:needs_review]).to eq(2)
  end
end
