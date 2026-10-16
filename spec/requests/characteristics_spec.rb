require "rails_helper"

RSpec.describe "GET /filters-glossary", type: :request do
  let(:workspace) { create(:workspace, slug: "characteristics-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  def viewer
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!("viewer"))
    user
  end

  let(:building) { create(:building, workspace: workspace) }
  let(:room) { create(:room, building: building, workspace: workspace) }

  describe "unauthenticated" do
    it "redirects to sign-in instead of rendering the glossary" do
      get filters_glossary_path

      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "signed in" do
    it "returns 200 with a category heading, an entry label, its short_code, and its long_description" do
      create(:room_characteristic, room: room, workspace: workspace, short_code: "projector",
             description: "Media: Projector", long_description: "A ceiling-mounted digital projector.")

      sign_in(viewer)
      get filters_glossary_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Media") # group heading, parsed from "Category: Value"
      expect(response.body).to include("Projector") # entry label
      expect(response.body).to include("projector") # short_code badge
      expect(response.body).to include("A ceiling-mounted digital projector.") # long_description
    end

    # The distinguishing rule between .filters (Find a Room's checkboxes) and
    # .glossary (this page): filterable: false entries are excluded from the
    # former but must still appear here. Normalization-stable short_code
    # ("projector", no punctuation) so the RoomCharacteristic row and the
    # CharacteristicDisplayRule join actually hits — RoomCharacteristic
    # doesn't normalize short_code itself, only CharacteristicDisplayRule
    # does (before_validation), per CodeNormalizer's header comment.
    it "still includes a characteristic marked filterable: false" do
      create(:room_characteristic, room: room, workspace: workspace, short_code: "projector",
             description: "Media: Projector", long_description: "Not filterable but still listed here.")
      create(:characteristic_display_rule, workspace: workspace, short_code: "projector", filterable: false)

      sign_in(viewer)
      get filters_glossary_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Not filterable but still listed here.")
    end

    it "lists entries within a group alphabetically by label" do
      create(:room_characteristic, room: room, workspace: workspace, short_code: "whiteboard",
             description: "Media: Whiteboard", long_description: "A whiteboard.")
      create(:room_characteristic, room: room, workspace: workspace, short_code: "projector",
             description: "Media: Projector", long_description: "A projector.")

      sign_in(viewer)
      get filters_glossary_path

      expect(response.body.index("Projector")).to be < response.body.index("Whiteboard")
    end
  end
end
