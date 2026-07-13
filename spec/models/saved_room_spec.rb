require "rails_helper"

# Saved rooms (shortlist): a user bookmarks rooms from the directory to
# return to later. Pure join — user ↔ room, workspace-scoped via Tenanted.
RSpec.describe SavedRoom do
  let(:workspace) { create(:workspace) }
  let(:building)  { create(:building, workspace: workspace) }
  let(:room)      { create(:room, building: building, workspace: workspace) }
  let(:user)      { create(:user) }

  it "saves a room once per user" do
    described_class.create!(user: user, room: room, workspace: workspace)
    dup = described_class.new(user: user, room: room, workspace: workspace)

    expect(dup).not_to be_valid
    expect { dup.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows different users to save the same room" do
    described_class.create!(user: user, room: room, workspace: workspace)
    other = create(:user)

    expect(described_class.create!(user: other, room: room, workspace: workspace)).to be_persisted
  end

  it "is destroyed with its room" do
    saved = described_class.create!(user: user, room: room, workspace: workspace)
    room.destroy!

    expect(described_class.exists?(saved.id)).to be(false)
  end
end
