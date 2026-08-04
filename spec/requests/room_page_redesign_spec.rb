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

    # LITERAL alt strings, per path, deliberately not `room.alt_for(:panorama)`.
    # The old assertion compared the rendered alt to whatever that method
    # returned, so it could not fail for any semantic reason — which is exactly
    # why the flat render shipped claiming to be a full 360-degree panorama
    # when it is a ~100-degree rectilinear crop. Two different literals here
    # means collapsing the two paths back into one is a test failure.
    # The :room factory AUTHORS panorama_alt ("Room panorama"), so the derived
    # path — the one every real room takes, and the one this branch changed —
    # is only reachable with it cleared. The old assertion did not notice: it
    # compared the rendered alt to room.alt_for(:panorama), which returned the
    # authored string on both paths.
    def clear_authored_alt! = room.update!(panorama_alt: nil)

    it "serves the flat render, proxied, and describes it as the opening frame" do
      clear_authored_alt!
      attach_equirect_panorama!

      get room_path(room)

      stage = page.find("#room_panorama_stage")
      expect(stage["data-panorama-preview-source"]).to eq("flat_render")
      # rails_storage_proxy_path, not rails_blob_path: the redirect route costs
      # a second round trip to the same Puma and re-expires every 5 minutes,
      # while the proxy controller serves it with http_cache_forever.
      expect(stage["data-panorama-preview-url-value"])
        .to eq(rails_storage_proxy_path(room.reload.flat_panorama, only_path: true))
      expect(stage).to have_css(
        "img[alt='Interior view of #{room.display_name}, the opening frame of an interactive 360-degree panorama']"
      )
      # The <img> and Pannellum's own `preview:` must be the SAME picture —
      # this is the central claim of the flat-render pane.
      expect(stage.find("img")["src"]).to eq(stage["data-panorama-preview-url-value"])
    end

    it "falls back to the poster variant when the render has not landed" do
      clear_authored_alt!
      room.panorama.attach(io: Rails.root.join("spec/fixtures/files/equirect.png").open,
                           filename: "pano.png", content_type: "image/png")
      expect(room.reload.flat_panorama).not_to be_attached

      get room_path(room)

      expect(response).to have_http_status(:ok)
      stage = page.find("#room_panorama_stage")
      expect(stage["data-panorama-preview-source"]).to eq("poster_fallback")
      # The :poster variant really IS the whole sweep (squashed), so the
      # 360-degree claim is TRUE here and false on the flat path — the alt must
      # differ between them. This example previously asserted no alt at all.
      expect(stage).to have_css("img[alt='360-degree panorama of #{room.display_name}']")
      # Same pin as the flat-render example: the <img> and Pannellum's
      # `preview:` must agree even on the fallback path.
      expect(stage.find("img")["src"]).to eq(stage["data-panorama-preview-url-value"])
    end

    # An AUTHORED alt is a curator's description of what is actually in the
    # room; that is more useful to a screen reader user than an accurate
    # description of a 100-degree crop, so the flat path must NOT override it.
    it "leaves an authored alt alone on the flat-render path" do
      room.update!(panorama_alt: "Tiered lecture hall with a chalkboard wall")
      attach_equirect_panorama!

      get room_path(room)

      expect(page.find("#room_panorama_stage"))
        .to have_css("img[alt='Tiered lecture hall with a chalkboard wall']")
    end

    # A render made under an OLD recipe (someone changed HFOV_DEG and did not
    # re-run the backfill) is still SERVED — a stale frame beats a squashed
    # strip — but it will visibly jump on Load, so it must not report itself as
    # "flat_render", which the docs define as "matches the viewer".
    it "flags a render made under a different projection recipe as stale" do
      attach_equirect_panorama!
      allow(Panorama::Rectilinear).to receive(:signature).and_return("hfov90-aspect2-w1024")

      get room_path(room)

      stage = page.find("#room_panorama_stage")
      expect(stage["data-panorama-preview-source"]).to eq("flat_render_stale")
      expect(stage["data-panorama-preview-url-value"])
        .to eq(rails_storage_proxy_path(room.reload.flat_panorama, only_path: true))
    end

    # "Never going to render" and "has not rendered yet" are the same picture
    # but different operator actions, and conflating them made the doc's own
    # next step "open a Rails console".
    it "distinguishes a permanently failed render from one that has not run yet" do
      perform_enqueued_jobs do
        room.panorama.attach(io: Rails.root.join("spec/fixtures/files/room.jpg").open,
                             filename: "not_equirect.jpg", content_type: "image/jpeg")
      end
      expect(room.reload.flat_render_failed?).to be(true)

      get room_path(room)

      stage = page.find("#room_panorama_stage")
      expect(stage["data-panorama-preview-source"]).to eq("poster_fallback_failed")
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
