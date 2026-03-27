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
    it "has one resource" do
      expect(Document.reflect_on_association(:resource).macro).to eq(:has_one)
    end
  end
end
