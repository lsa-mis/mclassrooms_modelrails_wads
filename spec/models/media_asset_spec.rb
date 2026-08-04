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

  it "requires an attached image of an accepted type" do
    asset = build(:media_asset, owner: room, workspace: workspace)
    asset.image.detach
    expect(asset).not_to be_valid
  end

  it "rejects an asset whose workspace differs from its owner's" do
    other = create(:workspace)
    asset = build(:media_asset, owner: room, workspace: other)

    expect(asset).not_to be_valid
    expect(asset.errors[:owner]).to be_present
  end

  it "orders by position then id" do
    c = create(:media_asset, owner: room, workspace: workspace, position: 2)
    a = create(:media_asset, owner: room, workspace: workspace, position: 1)

    expect(room.gallery.ordered.to_a).to eq([ a, c ])
  end
end
