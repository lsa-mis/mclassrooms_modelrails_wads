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

    it "generates a fallback slug for non-Latin names" do
      workspace = create(:workspace, name: "日本語の名前")
      expect(workspace.slug).to be_present
      expect(workspace.slug).not_to be_blank
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

    it "defaults max_projects to 3" do
      expect(Workspace.new.max_projects).to eq(3)
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

  describe "#effective_roles" do
    it "returns system defaults and workspace-specific roles" do
      owner_role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
        r.name = "Owner"
        r.permissions = { manage_workspace: true }
      end
      workspace = create(:workspace)
      custom_role = Role.create!(name: "Custom", slug: "custom", workspace: workspace)
      roles = workspace.effective_roles
      expect(roles).to include(owner_role)
      expect(roles).to include(custom_role)
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

  describe "cascade discard" do
    it "cascades discard to projects" do
      workspace = create(:workspace)
      user = create(:user)
      create(:membership, user: user, workspace: workspace)
      project = create(:project, workspace: workspace, created_by: user)

      workspace.discard!
      expect(project.reload).to be_discarded
    end
  end

  describe "name length" do
    it "limits name to 255 characters" do
      workspace = build(:workspace, name: "a" * 256)
      expect(workspace).not_to be_valid
    end
  end

  describe "max_members and max_projects validation" do
    it "requires max_members to be positive" do
      workspace = build(:workspace, max_members: 0)
      expect(workspace).not_to be_valid
    end

    it "requires max_projects to be positive" do
      workspace = build(:workspace, max_projects: 0)
      expect(workspace).not_to be_valid
    end
  end

  describe "logo attachment" do
    let(:workspace) { create(:workspace) }

    it "accepts valid image content types" do
      %w[image/png image/jpeg image/gif image/webp].each do |content_type|
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
