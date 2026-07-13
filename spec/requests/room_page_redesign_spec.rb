require "rails_helper"

# Room page redesign (2026-07 sprint v4, panel-reviewed): the media stage —
# panorama/photos as UI::Tabs panels (hidden, never removed: the WebGL viewer
# must survive pane swaps), identity overlaid on the stage (h1 = room name),
# a quiet branded band for the MAJORITY no-media case with an editor-gated
# "Add photos" affordance, documents/contacts/location in a rail, and the
# share button relabeled to its honest job (Copy link). Same tenancy pattern
# as spec/requests/rooms_spec.rb.
RSpec.describe "GET /rooms/:id (redesigned room page)", type: :request do
  let(:workspace) { create(:workspace, slug: "room-page-spec", personal: false) }

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
  let(:building) { create(:building, workspace: workspace, name: "Mason Hall") }
  let!(:room) do
    create(:room, building: building, workspace: workspace,
           facility_code: "MAS1401", instructional_seat_count: 45)
  end

  before { sign_in(viewer) }

  def page
    Capybara.string(response.body)
  end

  def attach_panorama!
    room.panorama.attach(io: File.open(Rails.root.join("spec/fixtures/files/room.jpg")),
                         filename: "pano.jpg", content_type: "image/jpeg")
  end

  it "renders the branded empty band (no error wording, no tabs) when the room has no media" do
    get room_path(room)

    band = page.find("[data-testid='empty-media-band']")
    expect(band).to have_css("h1", text: room.display_name)
    expect(response.body).not_to include("not found")
    expect(page).to have_no_css("[role='tablist']")
  end

  it "gates the empty band's Add photos affordance to those who can edit" do
    get room_path(room)
    expect(page).to have_no_link(I18n.t("rooms.show.add_photos"))

    sign_in(membership_with("admin"))
    get room_path(room)
    expect(page).to have_link(I18n.t("rooms.show.add_photos"))
  end

  it "renders the media stage with the identity overlay (h1) when a panorama exists" do
    attach_panorama!
    get room_path(room)

    stage = page.find("[data-testid='media-stage']")
    expect(stage).to have_css("h1", text: room.display_name)
    expect(stage).to have_text("45") # capacity rides the overlay
    expect(page).to have_no_css("[data-testid='empty-media-band']")
    # single medium → no tabs
    expect(page).to have_no_css("[role='tablist']")

    # Over-photo controls sit on OPAQUE surface-overlay plates (2026-07-13
    # contrast audit): contrast against an arbitrary poster is unknowable and
    # axe skips raster backgrounds, so the plate is the guarantee. The info
    # chip is min-44px — its tooltip wrapper is tabbable, making it a real
    # target under the AAA floor.
    overlay = stage.find("[data-panorama-target='overlay']")
    expect(overlay).to have_css("button.bg-surface-overlay", text: I18n.t("rooms.show.load_panorama"))
    expect(overlay).to have_css("span.min-h-11.min-w-11.bg-surface-overlay")
  end

  it "tabs the stage only when both panorama and photos exist, panes hidden not removed" do
    attach_panorama!
    create(:room_gallery_image, room: room, workspace: workspace)
    get room_path(room)

    expect(page).to have_css("[role='tablist'] [role='tab']", count: 2)
    # both panels are in the DOM (WebGL survival rule) — one hidden
    expect(page).to have_css("[role='tabpanel']", count: 2, visible: :all)
  end

  # Audit (Fried, Dave-approved): a card of "Not available" rows answers no
  # question. No contact record → one honest sentence; partial record → only
  # the fields that exist.
  describe "contact cards" do
    it "collapses to a single honest line when no contact exists" do
      get room_path(room)

      expect(page).to have_text(I18n.t("rooms.show.contacts.none"))
      expect(response.body).not_to include(I18n.t("rooms.show.not_available"))
    end

    it "renders only the fields that are present" do
      room.create_room_contact!(workspace: workspace, scheduling_email: "lsa-scheduling@umich.edu")
      get room_path(room)

      expect(page).to have_link("lsa-scheduling@umich.edu")
      expect(response.body).not_to include(I18n.t("rooms.show.not_available"))
      # empty support section renders no card at all
      expect(page).to have_no_text(I18n.t("rooms.show.contacts.support_heading"))
      expect(page).to have_no_text(I18n.t("rooms.show.contacts.scheduling_phone"))
    end
  end

  it "keeps documents and location in the rail and relabels share to Copy link" do
    floor = create(:floor, building: building, label: "1")
    room.update!(floor: floor)
    building.update!(address: "419 State St", city: "Ann Arbor", state: "MI", zip: "48109")
    get room_path(room)

    docs = page.find("[data-testid='documents-card']")
    expect(docs).to have_link(I18n.t("rooms.show.floor_plan_link"))
    expect(page).to have_css("[data-testid='location-card']", text: I18n.t("rooms.show.address"))
    expect(I18n.t("rooms.show.share.button")).to eq("Copy link")
    expect(page).to have_button(I18n.t("rooms.show.share.button"))
  end
end
