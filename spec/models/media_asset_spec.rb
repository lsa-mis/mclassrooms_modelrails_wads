require "rails_helper"

RSpec.describe MediaAsset do
  let(:workspace) { create(:workspace) }
  let(:room) { create(:room, workspace: workspace) }
  let(:record) { create(:media_asset) }

  it_behaves_like "a tenanted directory record"

  it "belongs to any owner polymorphically and is tenanted" do
    asset = create(:media_asset, owner: room, workspace: workspace)

    expect(asset.owner).to eq(room)
    expect(asset.owner_type).to eq("Room")
    expect(asset.workspace).to eq(workspace)
  end

  it "requires an owner" do
    expect(build(:media_asset, owner: nil, workspace: workspace)).not_to be_valid
  end

  describe "position" do
    it "defaults to 1, not 0" do
      expect(MediaAsset.new.position).to eq(1)
    end

    it "rejects a zero position" do
      asset = build(:media_asset, owner: room, workspace: workspace, position: 0)

      expect(asset).not_to be_valid
      expect(asset.errors[:position]).not_to be_empty
    end

    it "orders by position then id" do
      c = create(:media_asset, owner: room, workspace: workspace, position: 2)
      a = create(:media_asset, owner: room, workspace: workspace, position: 1)
      b = create(:media_asset, owner: room, workspace: workspace, position: 1)

      expect(MediaAsset.where(owner: room).ordered.to_a).to eq([ a, b, c ])
    end
  end

  describe "image attachment" do
    it "requires an attached image" do
      asset = build(:media_asset, owner: room, workspace: workspace)
      asset.image.detach

      expect(asset).not_to be_valid
      expect(asset.errors[:image]).not_to be_empty
    end

    it "accepts a small PNG" do
      expect(build(:media_asset, owner: room, workspace: workspace)).to be_valid
    end

    it "rejects a PDF" do
      asset = build(:media_asset, owner: room, workspace: workspace)
      asset.image.attach(io: StringIO.new("fake pdf content"),
                         filename: "gallery.pdf", content_type: "application/pdf")

      expect(asset).not_to be_valid
      expect(asset.errors[:image]).not_to be_empty
    end

    it "rejects an oversized (11MB) PNG" do
      asset = build(:media_asset, owner: room, workspace: workspace)
      asset.image.attach(io: StringIO.new("x" * 11.megabytes),
                         filename: "gallery.png", content_type: "image/png")

      expect(asset).not_to be_valid
      expect(asset.errors[:image]).not_to be_empty
    end
  end

  it "rejects an asset whose workspace differs from its owner's" do
    other = create(:workspace)
    asset = build(:media_asset, owner: room, workspace: other)

    expect(asset).not_to be_valid
    expect(asset.errors[:owner]).to be_present
  end

  # D9 caps the gallery at five in the UI (RoomsController#build_blank_gallery),
  # never in the schema — the model must not second-guess that.
  it "does not cap the number of assets an owner may have" do
    6.times { |n| create(:media_asset, owner: room, workspace: workspace, position: n + 1) }

    expect(room.gallery.count).to eq(6)
  end
end
