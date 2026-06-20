require "rails_helper"

RSpec.describe Resource, type: :model do
  describe "validations" do
    it "requires a title" do
      resource = build(:resource, title: nil)
      expect(resource).not_to be_valid
    end

    it "requires a project" do
      resource = build(:resource, project: nil)
      expect(resource).not_to be_valid
    end

    it "requires a created_by" do
      resource = build(:resource, created_by: nil)
      expect(resource).not_to be_valid
    end

    it "requires a resourceable" do
      resource = build(:resource, resourceable: nil)
      expect(resource).not_to be_valid
    end

    it "validates resourceable_type is allowed" do
      resource = build(:resource)
      resource.resourceable_type = "User"
      expect(resource).not_to be_valid
      expect(resource.errors[:resourceable_type]).to be_present
    end

    it "allows Document as resourceable_type" do
      resource = build(:resource)
      expect(resource).to be_valid
    end

    it "requires non-negative position" do
      resource = build(:resource, position: -1)
      expect(resource).not_to be_valid
      expect(resource.errors[:position]).to be_present
    end
  end

  describe "status enum" do
    it "defaults to draft" do
      expect(Resource.new.status).to eq("draft")
    end

    it "supports published" do
      resource = build(:resource, status: "published")
      expect(resource).to be_published
    end
  end

  describe "scopes" do
    it ".positioned orders by position asc" do
      project = create(:project)
      r2 = create(:resource, project: project, created_by: project.created_by, position: 2)
      r1 = create(:resource, project: project, created_by: project.created_by, position: 1)
      expect(project.resources.positioned.to_a).to eq([ r1, r2 ])
    end

    it ".published returns only published resources" do
      published = create(:resource, status: "published")
      create(:resource, status: "draft")
      expect(Resource.published).to include(published)
    end
  end

  describe "Discardable" do
    it "can be discarded" do
      resource = create(:resource)
      resource.discard!
      expect(resource).to be_discarded
      expect(Resource.kept).not_to include(resource)
    end
  end

  describe "Trackable" do
    it "creates an activity log on create" do
      resource = create(:resource)
      log = ActivityLog.where(trackable: resource, action: "resource.created").last
      expect(log).to be_present
    end
  end

  describe "#client_visible?" do
    it "is true when shared and published" do
      r = create(:resource, status: "published", shared_with_client: true)
      expect(r.client_visible?).to be(true)
    end

    it "is false when shared but still a draft" do
      r = create(:resource, status: "draft", shared_with_client: true)
      expect(r.client_visible?).to be(false)
    end

    it "is false when published but not shared" do
      r = create(:resource, status: "published", shared_with_client: false)
      expect(r.client_visible?).to be(false)
    end
  end
end
