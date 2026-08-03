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

    # The Load button sits on an OPAQUE surface-overlay plate (2026-07-13
    # contrast audit): contrast against an arbitrary poster is unknowable and
    # axe skips raster backgrounds, so the plate is the guarantee. The button
    # carries its own hint via aria-describedby (2026-07-14, UI::Tooltip's
    # interactive-control pattern) — no separate info chip.
    overlay = stage.find("[data-panorama-target='overlay']")
    button = overlay.find("button.bg-surface-overlay", text: I18n.t("rooms.show.load_panorama"))
    tip_id = button["aria-describedby"]
    expect(tip_id).to be_present
    expect(overlay).to have_css("##{tip_id}[role='tooltip']", text: I18n.t("rooms.show.panorama_hint"))
    # the standalone info chip is gone — the button IS the tooltip trigger now
    expect(overlay).to have_no_css("span.min-w-11.bg-surface-overlay")
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

  describe "panorama pane image" do
    include ActiveJob::TestHelper

    def attach_equirect_panorama!
      perform_enqueued_jobs do
        room.panorama.attach(io: Rails.root.join("spec/fixtures/files/equirect.png").open,
                             filename: "pano.png", content_type: "image/png")
      end
    end

    it "serves the flat render and says so in the DOM" do
      attach_equirect_panorama!

      get room_path(room)

      stage = page.find("#room_panorama_stage")
      expect(stage["data-panorama-preview-source"]).to eq("flat_render")
      expect(stage["data-panorama-preview-url-value"])
        .to eq(rails_blob_path(room.reload.flat_panorama, only_path: true))
      expect(stage).to have_css("img[alt='#{room.alt_for(:panorama)}']")
      # The <img> and Pannellum's own `preview:` must be the SAME picture —
      # this is the central claim of the flat-render pane.
      expect(stage.find("img")["src"]).to eq(stage["data-panorama-preview-url-value"])
    end

    it "falls back to the poster variant when the render has not landed" do
      room.panorama.attach(io: Rails.root.join("spec/fixtures/files/equirect.png").open,
                           filename: "pano.png", content_type: "image/png")
      expect(room.reload.flat_panorama).not_to be_attached

      get room_path(room)

      expect(response).to have_http_status(:ok)
      stage = page.find("#room_panorama_stage")
      expect(stage["data-panorama-preview-source"]).to eq("poster_fallback")
      # Same pin as the flat-render example: the <img> and Pannellum's
      # `preview:` must agree even on the fallback path.
      expect(stage.find("img")["src"]).to eq(stage["data-panorama-preview-url-value"])
    end

    # UI::AspectRatioComponent renders style="aspect-ratio: <ratio>". 2:1 is not
    # cosmetic: Panorama::Rectilinear renders width x width/2, and Pannellum
    # derives vfov from its container's aspect. A stage of any other ratio
    # object-covers the render and crops the framing the projection matched.
    it "pins the stage aspect and the camera to the projection's constants" do
      attach_equirect_panorama!

      get room_path(room)

      stage = page.find("#room_panorama_stage")
      expect(stage["style"]).to eq("aspect-ratio: #{Panorama::Rectilinear::ASPECT}")
      expect(stage["data-panorama-hfov-value"]).to eq(Panorama::Rectilinear::HFOV_DEG.to_s)
    end
  end
end
