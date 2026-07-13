require "rails_helper"

# Saved rooms (shortlist): POST saves, DELETE unsaves, both scoped hard to
# the signed-in user and the rooms they can actually see. Same tenancy
# pattern as spec/requests/rooms_spec.rb.
RSpec.describe "Saved rooms", type: :request do
  let(:workspace) { create(:workspace, slug: "saved-rooms-spec", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  let(:viewer)   { membership_with("viewer") }
  let(:building) { create(:building, workspace: workspace) }
  let!(:room)    { create(:room, building: building, workspace: workspace, facility_code: "SAV1001") }

  before { sign_in(viewer) }

  it "saves a room for the signed-in user" do
    expect {
      post saved_rooms_path, params: { room_id: room.id }
    }.to change { viewer.saved_rooms.count }.by(1)

    expect(response).to redirect_to(room_path(room))
  end

  it "is idempotent — a double save keeps one row" do
    post saved_rooms_path, params: { room_id: room.id }
    expect {
      post saved_rooms_path, params: { room_id: room.id }
    }.not_to change { SavedRoom.count }
  end

  it "refuses rooms the user cannot see (hidden)" do
    hidden = create(:room, :hidden, building: building, workspace: workspace, facility_code: "SAV1002")

    post saved_rooms_path, params: { room_id: hidden.id }
    expect(viewer.saved_rooms.count).to eq(0)
    expect(response).to have_http_status(:redirect) # RecordNotFound → app-wide rescue
  end

  it "unsaves via destroy, own rows only" do
    saved = SavedRoom.create!(user: viewer, room: room, workspace: workspace)

    expect {
      delete saved_room_path(saved)
    }.to change { SavedRoom.count }.by(-1)

    other = membership_with("viewer")
    foreign = SavedRoom.create!(user: other, room: room, workspace: workspace)
    delete saved_room_path(foreign)
    expect(SavedRoom.exists?(foreign.id)).to be(true) # not mine → untouched
  end

  it "responds with a turbo stream that flips the toggle and count" do
    post saved_rooms_path(format: :turbo_stream), params: { room_id: room.id }

    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include("save_toggle_room_#{room.id}")
    expect(response.body).to include("saved_rooms_count")
  end
end
