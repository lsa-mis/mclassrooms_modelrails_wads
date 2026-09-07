require "rails_helper"

# Workspace::Branding's examples. A concern trait is not instantiated, so its
# examples describe the model; this file is scoped by directory to the trait.
RSpec.describe Workspace, type: :model do
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

  describe "logo attachment" do
    let(:workspace) { create(:workspace) }

    # HEIC/HEIF included: it is the iPhone camera default, so rejecting it
    # bounces the most common source of a logo upload. Safe to accept — the
    # active_storage initializer records that both load and transform under
    # Vips.block_untrusted(true) after CVE-2026-66066, and Rails converts the
    # variant to PNG automatically because they are not web_image_content_types.
    it "accepts valid image content types" do
      %w[image/png image/jpeg image/gif image/webp image/heic image/heif].each do |content_type|
        workspace.logo.attach(io: StringIO.new("fake"), filename: "test.png", content_type: content_type)
        workspace.valid?
        expect(workspace.errors[:logo]).to be_empty, "Expected #{content_type} to be valid"
      end
    end

    it "rejects non-image content types" do
      workspace.logo.attach(io: StringIO.new("not an image"), filename: "doc.pdf", content_type: "application/pdf")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:logo]).to be_present
    end

    it "rejects files over 5MB" do
      workspace.logo.attach(io: StringIO.new("x" * 6.megabytes), filename: "big.png", content_type: "image/png")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:logo]).to be_present
    end
  end

  describe "logo_original attachment" do
    let(:workspace) { create(:workspace) }

    it "rejects non-image content types" do
      workspace.logo_original.attach(io: StringIO.new("not an image"), filename: "doc.pdf", content_type: "application/pdf")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:logo_original]).to be_present
    end

    it "rejects files over 10MB (original can be larger than cropped)" do
      workspace.logo_original.attach(io: StringIO.new("x" * 11.megabytes), filename: "big.png", content_type: "image/png")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:logo_original]).to be_present
    end
  end

  describe "logo_source" do
    it "defaults to initials" do
      workspace = create(:workspace)
      expect(workspace.logo_source).to eq("initials")
    end

    it "validates inclusion in upload and initials" do
      workspace = build(:workspace, logo_source: "upload")
      expect(workspace).to be_valid

      workspace.logo_source = "invalid"
      expect(workspace).not_to be_valid
    end
  end

  describe "#available_logo_sources" do
    it "returns upload and initials" do
      workspace = build(:workspace)
      expect(workspace.available_logo_sources).to eq(%w[upload initials])
    end
  end

  describe "primary_color (integer hue)" do
    it "defaults to 210 (blue)" do
      workspace = create(:workspace)
      expect(workspace.primary_color).to eq(210)
    end

    it "validates inclusion in 0..360" do
      workspace = build(:workspace, primary_color: 180)
      expect(workspace).to be_valid

      workspace.primary_color = -1
      expect(workspace).not_to be_valid

      workspace.primary_color = 361
      expect(workspace).not_to be_valid
    end

    it "allows nil" do
      workspace = build(:workspace, primary_color: nil)
      expect(workspace).to be_valid
    end
  end
end
