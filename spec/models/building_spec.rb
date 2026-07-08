require "rails_helper"

RSpec.describe Building, type: :model do
  let(:record) { create(:building) }

  it_behaves_like "a tenanted directory record"

  describe "validations" do
    it "requires bldrecnbr" do
      building = build(:building, bldrecnbr: nil)
      expect(building).not_to be_valid
    end

    it "requires name" do
      building = build(:building, name: nil)
      expect(building).not_to be_valid
    end

    it "enforces bldrecnbr uniqueness" do
      create(:building, bldrecnbr: "1000001")
      duplicate = build(:building, bldrecnbr: "1000001")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:bldrecnbr]).not_to be_empty
    end

    it "enforces bldrecnbr uniqueness globally, even across workspaces" do
      # Deliberate divergence from Campus/Unit: bldrecnbr is a U-M-wide
      # natural key, so uniqueness is NOT workspace-scoped.
      workspace = create(:workspace)
      create(:building, workspace: workspace, bldrecnbr: "1000002")
      duplicate = build(:building, workspace: create(:workspace), bldrecnbr: "1000002")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:bldrecnbr]).not_to be_empty
    end
  end

  describe "visibility scopes (D6: sync-owned in_feed vs. curation-owned hidden_at)" do
    let!(:listed_building) { create(:building, in_feed: true, hidden_at: nil) }
    let!(:in_feed_but_hidden) { create(:building, in_feed: true, hidden_at: Time.current) }
    let!(:not_in_feed_and_visible) { create(:building, in_feed: false, hidden_at: nil) }
    let!(:not_in_feed_and_hidden) { create(:building, in_feed: false, hidden_at: Time.current) }

    describe ".listed" do
      it "includes only records that are in_feed AND not hidden" do
        expect(Building.listed).to contain_exactly(listed_building)
      end
    end

    describe ".hidden" do
      it "includes every record with a hidden_at, regardless of in_feed" do
        expect(Building.hidden).to contain_exactly(in_feed_but_hidden, not_in_feed_and_hidden)
      end
    end

    describe ".not_in_feed" do
      it "includes every record with in_feed false, regardless of hidden_at" do
        expect(Building.not_in_feed).to contain_exactly(not_in_feed_and_visible, not_in_feed_and_hidden)
      end
    end
  end

  describe "#hidden?" do
    it "is true when hidden_at is present" do
      building = build(:building, hidden_at: Time.current)
      expect(building).to be_hidden
    end

    it "is false when hidden_at is nil" do
      building = build(:building, hidden_at: nil)
      expect(building).not_to be_hidden
    end
  end

  describe "#display_name" do
    it "returns just the name when there is no nickname" do
      building = build(:building, name: "Chemistry Building", nickname: nil)
      expect(building.display_name).to eq("Chemistry Building")
    end

    it "appends the nickname in parens when present" do
      building = build(:building, name: "Chemistry Building", nickname: "Chem")
      expect(building.display_name).to eq("Chemistry Building (Chem)")
    end
  end

  describe "photo attachment validations" do
    it "accepts a small PNG" do
      building = build(:building)
      building.photo.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "photo.png",
        content_type: "image/png"
      )
      expect(building).to be_valid
    end

    it "rejects a PDF" do
      building = build(:building)
      building.photo.attach(
        io: StringIO.new("fake pdf content"),
        filename: "photo.pdf",
        content_type: "application/pdf"
      )
      expect(building).not_to be_valid
      expect(building.errors[:photo]).not_to be_empty
    end

    it "rejects an oversized (11MB) PNG" do
      building = build(:building)
      building.photo.attach(
        io: StringIO.new("x" * 11.megabytes),
        filename: "photo.png",
        content_type: "image/png"
      )
      expect(building).not_to be_valid
      expect(building.errors[:photo]).not_to be_empty
    end
  end
end
