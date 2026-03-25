require "rails_helper"

RSpec.describe Workspace, type: :model do
  describe "validations" do
    it "requires a name" do
      workspace = build(:workspace, name: nil)
      expect(workspace).not_to be_valid
      expect(workspace.errors[:name]).to be_present
    end

    it "auto-deduplicates slugs for same name" do
      first = create(:workspace, name: "Acme Corp")
      second = create(:workspace, name: "Acme Corp")
      expect(first.slug).to eq("acme-corp")
      expect(second.slug).to eq("acme-corp-1")
    end

    it "rejects duplicate slugs at validation level" do
      create(:workspace, name: "Acme Corp")
      duplicate = build(:workspace, name: "Different Name")
      duplicate.slug = "acme-corp"
      expect(duplicate).not_to be_valid
    end
  end

  describe "slug generation" do
    it "generates slug from name" do
      workspace = create(:workspace, name: "Acme Corp")
      expect(workspace.slug).to eq("acme-corp")
    end

    it "uses slug for to_param" do
      workspace = create(:workspace, name: "Acme Corp")
      expect(workspace.to_param).to eq("acme-corp")
    end
  end

  describe "plan enum" do
    it "defaults to free" do
      workspace = Workspace.new
      expect(workspace.plan).to eq("free")
    end

    it "supports pro and enterprise" do
      expect(build(:workspace, plan: "pro")).to be_valid
      expect(build(:workspace, plan: "enterprise")).to be_valid
    end
  end

  describe "settings defaults" do
    it "defaults max_members to 5" do
      expect(Workspace.new.max_members).to eq(5)
    end

    it "defaults max_teams to 3" do
      expect(Workspace.new.max_teams).to eq(3)
    end
  end

  describe "Discardable" do
    let(:workspace) { create(:workspace) }

    it "can be discarded" do
      workspace.discard!
      expect(workspace).to be_discarded
    end

    it "is excluded from kept scope when discarded" do
      workspace.discard!
      expect(Workspace.kept).not_to include(workspace)
    end

    it "can be undiscarded" do
      workspace.discard!
      workspace.undiscard!
      expect(workspace).not_to be_discarded
    end
  end

  describe "logo" do
    it "generates initials from name" do
      workspace = build(:workspace, name: "Acme Corp")
      expect(workspace.initials).to eq("AC")
    end

    it "limits initials to 2 characters" do
      workspace = build(:workspace, name: "The Big Company Name")
      expect(workspace.initials).to eq("TB")
    end
  end
end
