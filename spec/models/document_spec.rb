require "rails_helper"

RSpec.describe Document, type: :model do
  describe "rich text" do
    it "has a body via Action Text" do
      doc = Document.create!
      doc.body = "Hello world"
      doc.save!
      expect(doc.reload.body.to_plain_text).to eq("Hello world")
    end
  end

  describe "association" do
    it "can have a resource" do
      doc = Document.create!
      project = create(:project)
      resource = Resource.create!(
        project: project,
        resourceable: doc,
        title: "Test",
        created_by: project.created_by
      )
      expect(doc.reload.resource).to eq(resource)
    end
  end
end
