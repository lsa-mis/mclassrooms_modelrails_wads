require "rails_helper"

RSpec.describe Project, type: :model do
  describe "validations" do
    it "requires a name" do
      project = build(:project, name: nil)
      expect(project).not_to be_valid
    end

    it "requires a workspace" do
      project = build(:project, workspace: nil)
      expect(project).not_to be_valid
    end

    it "requires a created_by user" do
      project = build(:project, created_by: nil)
      expect(project).not_to be_valid
    end
  end

  describe "slug generation" do
    it "generates slug from name" do
      project = create(:project, name: "My Project")
      expect(project.slug).to eq("my-project")
    end

    it "auto-deduplicates slugs within workspace" do
      workspace = create(:workspace)
      user = create(:user)
      create(:membership, user: user, workspace: workspace)
      first = create(:project, name: "Alpha", workspace: workspace, created_by: user)
      second = create(:project, name: "Alpha", workspace: workspace, created_by: user)
      expect(first.slug).to eq("alpha")
      expect(second.slug).to eq("alpha-1")
    end

    it "allows same slug in different workspaces" do
      first = create(:project, name: "Alpha")
      second = create(:project, name: "Alpha")
      expect(first.slug).to eq("alpha")
      expect(second.slug).to eq("alpha")
    end

    it "uses slug for to_param" do
      project = create(:project, name: "My Project")
      expect(project.to_param).to eq("my-project")
    end
  end

  describe "Discardable" do
    let(:project) { create(:project) }

    it "can be discarded" do
      project.discard!
      expect(project).to be_discarded
    end

    it "is excluded from kept scope" do
      project.discard!
      expect(Project.kept).not_to include(project)
    end
  end

  describe "initials" do
    it "generates initials from name" do
      project = build(:project, name: "Design Sprint")
      expect(project.initials).to eq("DS")
    end
  end

  describe "max_projects enforcement" do
    it "validates workspace has capacity" do
      workspace = create(:workspace, max_projects: 1)
      user = create(:user)
      create(:membership, user: user, workspace: workspace)
      create(:project, workspace: workspace, created_by: user)
      second = build(:project, workspace: workspace, created_by: user)
      expect(second).not_to be_valid
      expect(second.errors[:base]).to be_present
    end
  end
end
