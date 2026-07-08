require "rails_helper"

RSpec.describe RoomContact, type: :model do
  let(:record) { create(:room_contact) }

  it_behaves_like "a tenanted directory record"

  describe "validations" do
    it "requires a room" do
      contact = build(:room_contact, room: nil, workspace: create(:workspace))
      expect(contact).not_to be_valid
    end

    it "is invalid with a second contact for the same room" do
      room = create(:room)
      create(:room_contact, room: room)
      duplicate = build(:room_contact, room: room)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:room_id]).not_to be_empty
    end

    it "allows contacts on different rooms" do
      create(:room_contact)
      other = build(:room_contact)

      expect(other).to be_valid
    end

    it "does not require the scheduling or support attribute blocks (nil-tolerant, Brief §4.4)" do
      contact = build(:room_contact,
        scheduling_name: nil, scheduling_email: nil, scheduling_phone: nil,
        scheduling_detail_url: nil, scheduling_usage_guidelines_url: nil,
        support_department_id: nil, support_department_description: nil,
        support_email: nil, support_phone: nil, support_url: nil)

      expect(contact).to be_valid
    end
  end

  describe "attribute blocks" do
    it "stores the scheduling block" do
      contact = create(:room_contact,
        scheduling_name: "Registrar's Office",
        scheduling_email: "registrar@umich.edu",
        scheduling_phone: "734-555-0100",
        scheduling_detail_url: "https://example.edu/rooms/101",
        scheduling_usage_guidelines_url: "https://example.edu/rooms/101/guidelines")

      expect(contact.scheduling_name).to eq("Registrar's Office")
      expect(contact.scheduling_email).to eq("registrar@umich.edu")
      expect(contact.scheduling_phone).to eq("734-555-0100")
      expect(contact.scheduling_detail_url).to eq("https://example.edu/rooms/101")
      expect(contact.scheduling_usage_guidelines_url).to eq("https://example.edu/rooms/101/guidelines")
    end

    it "stores the support block" do
      contact = create(:room_contact,
        support_department_id: "1234",
        support_department_description: "LSA Facilities",
        support_email: "support@umich.edu",
        support_phone: "734-555-0199",
        support_url: "https://example.edu/support")

      expect(contact.support_department_id).to eq("1234")
      expect(contact.support_department_description).to eq("LSA Facilities")
      expect(contact.support_email).to eq("support@umich.edu")
      expect(contact.support_phone).to eq("734-555-0199")
      expect(contact.support_url).to eq("https://example.edu/support")
    end
  end
end
