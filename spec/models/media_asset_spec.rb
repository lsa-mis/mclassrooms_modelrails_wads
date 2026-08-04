require "rails_helper"

RSpec.describe MediaAsset do
  let(:workspace) { create(:workspace) }
  let(:room) { create(:room, workspace: workspace) }

  it "belongs to any owner polymorphically and is tenanted" do
    asset = create(:media_asset, owner: room, workspace: workspace)

    expect(asset.owner).to eq(room)
    expect(asset.owner_type).to eq("Room")
    expect(asset.workspace).to eq(workspace)
  end

  it "defaults position to 1, not 0" do
    expect(MediaAsset.new.position).to eq(1)
  end
end
