require "rails_helper"

RSpec.describe Note, type: :model do
  let(:record) { create(:note) }

  it_behaves_like "a tenanted directory record"

  describe "polymorphic notable" do
    it "can belong to a Room" do
      room = create(:room)
      note = create(:note, notable: room, workspace: room.workspace)
      expect(note.notable).to eq(room)
    end

    it "can belong to a Building" do
      building = create(:building)
      note = create(:note, notable: building, workspace: building.workspace)
      expect(note.notable).to eq(building)
    end

    it "is invalid for a notable_type outside Room/Building" do
      note = build(:note, notable_type: "User", notable_id: create(:user).id)
      expect(note).not_to be_valid
      expect(note.errors[:notable_type]).not_to be_empty
    end
  end

  describe "author" do
    it "requires an author" do
      note = build(:note, author: nil)
      expect(note).not_to be_valid
    end
  end

  describe "rich text body" do
    it "supports has_rich_text body" do
      note = create(:note, body: "Hello there")
      expect(note.body.to_plain_text).to eq("Hello there")
    end

    it "is invalid with a blank body" do
      note = build(:note, body: nil)
      expect(note).not_to be_valid
    end
  end

  describe "alert" do
    it "defaults to false" do
      expect(Note.new.alert).to eq(false)
    end
  end

  describe "scopes" do
    it ".alerts returns only alert notes" do
      alert_note = create(:note, :alert)
      create(:note)
      expect(Note.alerts).to contain_exactly(alert_note)
    end

    it ".plain_notes returns only non-alert notes" do
      plain_note = create(:note)
      create(:note, :alert)
      expect(Note.plain_notes).to contain_exactly(plain_note)
    end

    it ".roots returns only top-level notes" do
      root = create(:note)
      create(:note, :reply, parent: root)
      expect(Note.roots).to contain_exactly(root)
    end
  end

  describe "one-level threading" do
    it "allows a reply to a root note" do
      root = create(:note)
      reply = build(:note, :reply, parent: root)
      expect(reply).to be_valid
    end

    it "is invalid when the parent is itself a reply" do
      root = create(:note)
      reply = create(:note, :reply, parent: root)
      grandchild = build(:note, :reply, parent: reply)

      expect(grandchild).not_to be_valid
      expect(grandchild.errors[:parent_id]).not_to be_empty
    end

    it "cascades destroy to replies" do
      root = create(:note)
      create(:note, :reply, parent: root)

      expect { root.destroy! }.to change(Note, :count).by(-2)
    end
  end

  describe "Broadcastable" do
    it "includes the Broadcastable concern" do
      expect(Note.include?(Broadcastable)).to be true
    end

    it "broadcasts to the notable record" do
      note = create(:note)
      expect(note.send(:broadcast_target)).to eq(note.notable)
    end
  end
end
