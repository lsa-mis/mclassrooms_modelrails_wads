require "rails_helper"
require "rake"

RSpec.describe "Media::AltCoverage" do
  before(:all) do
    Rails.application.load_tasks
  end

  it "counts needs_review vs attached per model/slot" do
    create(:media_asset, image_alt: nil, image_derived_ok: false) # needs_review
    create(:media_asset, image_alt: "authored")                    # authored

    rows = Media::AltCoverage.report
    gallery = rows.find { |r| r[:model] == "MediaAsset" && r[:slot] == :image }
    expect(gallery[:attached]).to eq(2)
    expect(gallery[:needs_review]).to eq(1)
  end
end
