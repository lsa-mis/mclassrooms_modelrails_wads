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

  describe "subject" do
    it "accepts a subject in the owner's vocabulary and rejects one outside it" do
      expect(build(:media_asset, owner: room, workspace: workspace, subject: "rack")).to be_valid
      expect(build(:media_asset, owner: room, workspace: workspace, subject: "spaceship")).not_to be_valid
      expect(build(:media_asset, owner: room, workspace: workspace, subject: nil)).to be_valid
    end

    it "reads back a retired subject that is already persisted" do
      asset = create(:media_asset, owner: room, workspace: workspace, subject: "inner_door")
      stub_const("Room::SUBJECTS", Room::SUBJECTS.merge(
        inner_door: { key: "media.derived_alt.room.inner_door", retired: true }
      ))

      expect(asset.reload).to be_valid
      expect { asset.alt_for(:image) }.not_to raise_error
    end

    it "ranks by subject, then position, with unclassified last" do
      unclassified = create(:media_asset, owner: room, workspace: workspace, position: 1, subject: nil)
      rack         = create(:media_asset, owner: room, workspace: workspace, position: 5, subject: "rack")
      front        = create(:media_asset, owner: room, workspace: workspace, position: 9, subject: "front")

      expect(room.gallery_ordered).to eq([ front, rack, unclassified ])
    end

    # Regression for a hazard the reviewer caught: an unsaved row (id: nil)
    # tying a PERSISTED row on [subject_rank, position] used to blow up
    # sort_by with ArgumentError ("comparison of Array with Array failed"),
    # because `nil <=> Integer` is nil. `position` has no uniqueness
    # constraint, so this tie is ordinary, not exotic — Room#gallery_ordered
    # must fall back the unsaved row's id to Infinity so it sorts last
    # instead of raising.
    it "does not raise when an unsaved asset ties a persisted one on [subject, position]" do
      persisted = create(:media_asset, owner: room, workspace: workspace, position: 3, subject: "rack")
      unsaved   = build(:media_asset, owner: room, workspace: workspace, position: 3, subject: "rack")
      # Stub rather than `room.gallery << unsaved`: appending to a has_many
      # collection on a persisted owner autosaves the child, which would
      # give `unsaved` an id and defeat the point of this test.
      allow(room).to receive(:gallery).and_return([ persisted, unsaved ])

      expect { room.gallery_ordered }.not_to raise_error
      expect(room.gallery_ordered).to eq([ persisted, unsaved ])
    end
  end
end
