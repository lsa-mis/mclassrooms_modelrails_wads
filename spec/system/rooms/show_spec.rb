require "rails_helper"

# MiClassrooms Phase 4 Task 5 (Brief §5.3): full system-spec coverage for the
# room detail page — header, characteristic chips, contact fallback, notes,
# the media suite (photo lightbox, gallery, panorama, seating chart, floor
# plan), the share confirmation, and the axe-AAA both-themes sweep (the
# definitive a11y gate for the whole page, media included). Mirrors
# spec/system/find_a_room_spec.rb's tenancy setup: shared-posture stub +
# workspace-scoped building/room fixtures + sign_in_via_form.
RSpec.describe "Room show", type: :system do
  let!(:workspace) { create(:workspace, slug: "directory", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:building) { create(:building, name: "Mason Hall", workspace: workspace) }
  let!(:floor) { create(:floor, building: building, workspace: workspace, label: "2") }
  let!(:room) do
    create(:room, building: building, workspace: workspace, floor: floor, room_number: "1200",
           facility_code: "MAS1200", instructional_seat_count: 80, ada_seat_count: 2)
  end

  # Normalization-stable short_code (RoomCharacteristic#short_code is NOT
  # model-normalized, unlike CharacteristicDisplayRule#short_code, which
  # CodeNormalizer strips non-alphanumerics from) — "projector" survives
  # normalization unchanged, so the presenter's icon-key join hits and the
  # chip renders a real icon instead of falling back to FALLBACK_ICON.
  let!(:room_characteristic) do
    create(:room_characteristic, room: room, workspace: workspace,
           short_code: "projector", description: "Media: Projector")
  end

  before do
    create(:characteristic_display_rule, workspace: workspace,
           short_code: "projector", icon_key: "computer_desktop")
  end

  # Auto-joins `workspace` (the :shared posture stubbed above is already
  # active by the time this runs) under TenancyConfig.shared_join_role — a
  # non-admin role, matching the room's viewer-facing render (no inactive
  # banner, no admin-only affordances).
  let(:user) { create(:user) }

  # Regression coverage for two bugs caught in review then left unprotected
  # (the covering spec was written, then deleted before commit):
  #   1. notes/_list.html.erb's `:rich_text_body` eager-load — without it,
  #      rendering more than one note fires a query per note on the
  #      has_rich_text association, which trips Bullet.raise (enabled below
  #      via the app's `Bullet.raise = true` test config) as an N+1.
  #   2. notes/_note.html.erb's `<%= note.body %>` — using `note.body` (no
  #      `<%=`) swallows the RichText output; asserting the rendered body
  #      text below fails if that regresses.
  # One alert + one plain root note on the room, one note on the building —
  # three notes total, enough to trip the N+1 if the preload regresses.
  let!(:room_alert_note) do
    create(:note, :alert, notable: room, workspace: workspace, author: user,
           body: "Projector bulb needs replacement")
  end
  let!(:room_plain_note) do
    create(:note, notable: room, workspace: workspace, author: user,
           body: "Room was repainted last spring")
  end
  let!(:building_note) do
    create(:note, notable: building, workspace: workspace, author: user,
           body: "Building elevator under maintenance")
  end

  # Task 5: the full media suite, attached so every branch of
  # rooms/_media.html.erb renders real markup for the axe sweep below (not
  # just the "nothing attached" fallback). `room.jpg`/`seating_chart.pdf` are
  # dedicated fixtures (marcel-identified as image/jpeg and application/pdf
  # respectively); the gallery reuses the shared avatar.png fixture via the
  # :room_gallery_image factory.
  before do
    room.photo.attach(io: file_fixture("room.jpg").open,
                       filename: "MAS1200.jpg", content_type: "image/jpeg")
    room.panorama.attach(io: file_fixture("room.jpg").open,
                          filename: "MAS1200-360.jpg", content_type: "image/jpeg")
    room.seating_chart.attach(io: file_fixture("seating_chart.pdf").open,
                               filename: "MAS1200-seating.pdf", content_type: "application/pdf")
    create_list(:room_gallery_image, 2, room: room, workspace: workspace)
  end

  before { sign_in_via_form(user) }

  # Scopes the axe sweep to the full WCAG 2.2 conformance set (A + AA + AAA,
  # the project's compliance target). wcag2aaa alone only runs axe's 3
  # AAA-only rules (color-contrast-enhanced, identical-links-same-purpose,
  # meta-refresh-no-exceptions) — baseline rules (label, button-name,
  # image-alt, aria-prohibited-attr, etc.) are tagged wcag2a/wcag2aa and were
  # never exercised under that filter. See find_a_room_spec.rb.
  #
  # Widening this surfaced a real aria-prohibited-attr failure (wcag2a,
  # SC 4.1.2): shared/_toasts.html.erb's always-present `#toast-pills` /
  # `#toast-cards` containers had `aria-label` on a bare `<div>` (implicit
  # role "generic", which doesn't support naming). Fixed at the source by
  # adding `role="region"` to both containers — every page benefits, not
  # just this one.
  let(:axe_options) { PlaywrightAccessibility::DEFAULT_AXE_OPTIONS.dup }

  it "renders the header, chips, media, notes, and share accessibly in both themes" do
    # Headless Chrome exposes navigator.share, which would relabel the button to
    # "Share" and open the OS sheet; force the clipboard-fallback path here so
    # the "Copy link" button + copied confirmation stay deterministic. The native
    # share sheet is exercised in its own example below.
    cdp_add_init_script("Object.defineProperty(navigator,'share',{value:undefined,configurable:true});")
    visit room_path(room)

    expect(page).to have_selector("h1", text: room.display_name)
    expect(page).to have_content(
      I18n.t("rooms.show.capacity", students: room.instructional_seat_count, ada: room.ada_seat_count)
    )
    expect(page).to have_content("Projector")

    # room.room_contact is nil — every contact field falls back to
    # "Not available" rather than raising on a missing association.
    # room.room_contact is nil — the contact cards collapse to one honest
    # sentence instead of a wall of "Not available" rows (audit, Fried).
    expect(page).to have_content(I18n.t("rooms.show.contacts.none"))

    # Room notes (own alert + own plain) and the building's note all render
    # their RichText body content — protects the swallowed-body fix. Bullet
    # is active in test (raises on N+1), so rendering all three notes here
    # also protects the :rich_text_body eager-load fix implicitly: this
    # example would raise Bullet::Notification::UnoptimizedQueryError instead
    # of reaching these assertions if the preload regressed.
    expect(page).to have_content(room_alert_note.body.to_plain_text)
    expect(page).to have_content(room_plain_note.body.to_plain_text)
    expect(page).to have_content(building_note.body.to_plain_text)

    # Photo lightbox: UI::Dialog's own `modal` controller owns the focus
    # trap/Escape/restore — no bespoke JS needed. Opening the dialog shows
    # the full-size image; Escape closes it and returns focus to the thumb
    # that opened it (modal_controller#open records document.activeElement,
    # #close refocuses it).
    # Scoped to the native `dialog` tag (not the bare `[role='dialog']`
    # attribute selector) — biscuit-rails' cookie-consent banner also carries
    # `role="dialog"` on a plain `<div>`, and it stays on the page throughout,
    # so an unscoped selector both false-matches it opened and never closes
    # it after Escape.
    # Panorama pane is the media stage's default tab. Clicking "Load 360°"
    # must (1) hide the WHOLE overlay — a lingering inset-0 overlay swallows
    # every drag/zoom, the 2026-07-13 interaction bug — and (2) hand focus to
    # the viewer (hiding the focused button drops focus to <body>, WCAG
    # 2.4.3). Only non-WebGL DOM outcomes are asserted: pannellum builds
    # .pnlm-container and takes focus even when headless Chromium lacks WebGL
    # (it renders its error message inside), so this is CI-safe.
    expect(page).to have_button(I18n.t("rooms.show.load_panorama"))
    # Audit the PRE-load stage state before clicking: the Load button + hint
    # chip over the poster photo only exist now — the end-of-example sweep
    # runs after the overlay is hidden and would never see them (this is the
    # state the mc-transparent-over-media / 44px checks exist to guard).
    expect(axe_violations(axe_options, include: "#room_panorama_stage")).to be_empty
    click_button I18n.t("rooms.show.load_panorama")
    expect(page).to have_css("#room_panorama_stage .pnlm-container")
    expect(page).to have_no_css("[data-panorama-target='overlay']", visible: :visible)
    expect(page.evaluate_script("document.activeElement.classList.contains('pnlm-container')")).to be(true)

    # Redesign v4: photos are the stage's second tab — switching panes hides
    # (never removes) the panorama panel, per the WebGL-survival rule.
    click_button I18n.t("rooms.show.media_tabs.photos")
    find("[data-testid='room-photo-thumb']").click
    expect(page).to have_css("dialog[role='dialog'] img")
    send_keys(:escape)
    expect(page).to have_no_css("dialog[role='dialog']")
    expect(page.evaluate_script("document.activeElement.dataset.testid")).to eq("room-photo-thumb")

    # Floor-plan link renders (the room has a floor) but is NOT clicked —
    # RoomsController#floor_plan ships in Task 6, so the route 500s until then.
    expect(page).to have_link(I18n.t("rooms.show.floor_plan_link"))

    click_button I18n.t("rooms.show.share.button")
    expect(page).to have_content(I18n.t("rooms.show.share.copied"))

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  describe "hero identity placement (2026-07-15 panel, Option A)" do
    it "sits as a solid block BELOW the photo on mobile and overlays it from md up" do
      visit room_path(room)
      ensure_light_mode

      band_vs_pano = lambda do
        cdp_evaluate(<<~JS)
          (() => {
            const stage = document.querySelector("[data-testid='media-stage']");
            const pano = document.querySelector("#room_panorama_stage");
            const band = [...stage.children].find((c) => c.querySelector("h1"));
            const p = pano.getBoundingClientRect(), b = band.getBoundingClientRect();
            return { panoBottom: Math.round(p.bottom), bandTop: Math.round(b.top) };
          })()
        JS
      end

      cdp_resize(390, 1100)
      mobile = band_vs_pano.call
      expect(mobile["bandTop"]).to be >= (mobile["panoBottom"] - 2),
        "mobile: identity band should sit BELOW the panorama " \
        "(bandTop=#{mobile['bandTop']} panoBottom=#{mobile['panoBottom']})"

      cdp_resize(1280, 900)
      desktop = band_vs_pano.call
      expect(desktop["bandTop"]).to be < desktop["panoBottom"],
        "desktop: identity band should overlay the panorama bottom " \
        "(bandTop=#{desktop['bandTop']} panoBottom=#{desktop['panoBottom']})"
    end
  end

  describe "native share (2026-07-15 panel)" do
    it "opens the OS share sheet and relabels the trigger when navigator.share is available" do
      # Stub the share sheet before the page's JS runs so the controller sees it
      # on connect. Record the payload the app hands it.
      cdp_add_init_script(<<~JS)
        window.__sharePayload = undefined;
        navigator.share = (data) => { window.__sharePayload = data; return Promise.resolve(); };
        navigator.canShare = () => true;
      JS
      visit room_path(room)

      trigger = find("[data-share-target='button']")
      expect(trigger).to have_text(I18n.t("rooms.show.share.native_button")) # relabelled "Share"

      trigger.click
      payload = nil
      15.times do
        payload = cdp_evaluate("window.__sharePayload || null")
        break if payload
        sleep 0.1
      end
      expect(payload).to be_present
      expect(payload["url"]).to include(room.rmrecnbr)               # the canonical room link
      expect(page).to have_no_content(I18n.t("rooms.show.share.copied")) # the sheet is the feedback
    end
  end
end
