require "rails_helper"

# Find a Room redesign (2026-07 design sprint, approved direction): a compact
# filter card — one merged search box (`q`), always-visible minimum capacity,
# promoted "popular features" chips — with the characteristic long tail behind
# a native <details> "More filters" disclosure; count/sort header INSIDE the
# results Turbo frame (so live feedback survives scrolling); removable
# applied-filter chips; buildings grid dropped. Same tenancy stubbing pattern
# as spec/requests/rooms_spec.rb.
RSpec.describe "GET /find-a-room (redesigned filter card)", type: :request do
  include ClassroomBuilders

  let(:workspace) { create(:workspace, slug: "redesign-spec-workspace", personal: false) }

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
  let(:floor)    { create(:floor, building: building, label: "1") }
  let!(:room)    { classroom(building, "1401", 45, codes: %w[intrscreen movetablet whtbrd blackout], floor: floor) }

  before { sign_in(viewer) }

  def page
    Capybara.string(response.body)
  end

  it "renders one merged search box instead of separate building/room inputs" do
    get find_a_room_path

    expect(page).to have_css("input[name='q']")
    expect(page).to have_no_css("input[name='building']")
    expect(page).to have_no_css("input[name='room']")
  end

  # Prototype labeling: compact visible labels, but accessible names stay
  # descriptive — the aria-label is a superset of the visible label text
  # (WCAG 2.5.3 Label in Name), and the placeholder is only a hint.
  it "labels search compactly with a descriptive accessible name and prototype placeholder" do
    get find_a_room_path

    input = page.find("input[name='q']")
    expect(input["placeholder"]).to eq(I18n.t("rooms.filters.search_placeholder"))
    expect(input["aria-label"]).to eq(I18n.t("rooms.filters.search_accessible_label"))
    expect(page).to have_css("label[for='filter_q']", text: /\A#{I18n.t("rooms.filters.search_label")}\z/)
    expect(page).to have_css("label[for='filter_capacity_min']", normalize_ws: true,
                             text: /\A#{I18n.t('rooms.filters.capacity_min_label')}\z/)
    # 2026-07-15 panel: "Min. capacity" is self-describing, so the accessible
    # name carries the "minimum" qualifier itself — the separate hint that
    # floated orphaned below the box is gone (nothing to wire via describedby).
    expect(page).to have_no_css("#filter_capacity_min-hint")
    expect(page.find("input[name='capacity_min']")["aria-describedby"]).to be_blank
  end

  it "keeps the whole capacity range (min AND max) always visible, out of the More-filters disclosure" do
    get find_a_room_path

    # 2026-07-16: min+max are one range promoted above the fold — neither is
    # tucked behind the disclosure anymore.
    expect(page).to have_css("input[name='capacity_min']")
    expect(page).to have_css("input[name='capacity_max']")
    expect(page).to have_no_css("details#more_filters input[name='capacity_max']", visible: :all)
  end

  # A `max=` on these inputs makes form.requestSubmit() FAIL constraint
  # validation silently for over-bound values — typing 9999 froze every
  # subsequent live filter change (verified in-browser). An over-bound minimum
  # should return an honest "0 rooms found" instead.
  it "leaves capacity inputs unclamped so over-bound values get zero results, not a blocked submit" do
    get find_a_room_path

    expect(page).to have_css("input[name='capacity_min']:not([max])")
    expect(page).to have_css("input[name='capacity_max']:not([max])")
  end

  it "promotes popular features as chips outside the disclosure, without duplicating them inside" do
    get find_a_room_path

    expect(page).to have_css("input[type='checkbox'][name='characteristics[]'][value='intrscreen']")
    expect(page).to have_no_css("details#more_filters input[value='intrscreen']", visible: :all)
    # the long tail stays inside the disclosure
    expect(page).to have_css("details#more_filters input[type='checkbox'][name='characteristics[]'][value='blackout']", visible: :all)
  end

  it "surfaces the School/College (unit) select in the always-visible filters, not the disclosure, and drops the per-page select" do
    get find_a_room_path

    expect(page).to have_css("select[name='unit_id']")
    expect(page).to have_no_css("details#more_filters select[name='unit_id']", visible: :all)
    expect(page).to have_no_css("select[name='per']", visible: :all)
  end

  it "makes the More-filters toggle discoverable with a state-aware label" do
    get find_a_room_path

    summary = page.find("details#more_filters > summary")
    # Discoverability (2026-07-14): a resting filled plate, not a bare heading.
    expect(summary[:class]).to include("bg-surface-sunken")
    # State-aware verb — both labels ship; CSS (group-open) swaps which shows.
    expect(summary).to have_text(I18n.t("rooms.filters.more_filters"))
    expect(summary).to have_text(I18n.t("rooms.filters.hide_filters"))
  end

  it "puts the sort select inside the results frame, associated with the filter form" do
    get find_a_room_path

    expect(page).to have_css("turbo-frame#find_a_room_results select[name='sort'][form='find_a_room_form']")
  end

  it "renders applied filters as removable chip links inside the results frame" do
    get find_a_room_path(q: "Mason", capacity_min: "40")

    frame = page.find("turbo-frame#find_a_room_results")
    expect(frame).to have_link(I18n.t("rooms.index.summary.query", value: "Mason"))
    remove_query = frame.find_link(I18n.t("rooms.index.summary.query", value: "Mason"))["href"]
    expect(remove_query).not_to include("q=")
    expect(remove_query).to include("capacity_min=40")
  end

  it "no longer renders the buildings card grid" do
    get find_a_room_path

    expect(page).to have_no_css("turbo-frame#find_a_room_results aside")
  end

  it "keeps an sr-only card title, with clear-all and the glossary link OUT of the filter card, and a page subtitle" do
    get find_a_room_path(q: "Mason")

    form = page.find("form#find_a_room_form")
    # The "Filters" title is sr-only (still in the DOM for screen-reader heading
    # nav); clear-all lives in the results toolbar; and the standalone glossary
    # link was dropped — the per-filter popovers are the inline glossary.
    expect(form).to have_text(I18n.t("rooms.filters.card_title"))
    expect(form).to have_no_link(I18n.t("rooms.filters.glossary_link"))
    expect(form).to have_no_link(I18n.t("rooms.filters.reset"))
    expect(page).to have_text(I18n.t("rooms.index.subtitle"))
  end

  it "has exactly one clear-all — in the results toolbar — and only when filters are applied" do
    get find_a_room_path(q: "Mason")
    expect(page).to have_link(I18n.t("rooms.filters.reset"), count: 1)
    expect(page.find("turbo-frame#find_a_room_results")).to have_link(I18n.t("rooms.filters.reset"))

    get find_a_room_path
    expect(page).to have_no_link(I18n.t("rooms.filters.reset"))
  end

  it "counts only the panel's characteristic filters on the More-filters summary, ignoring promoted chips and now-visible unit/capacity" do
    get find_a_room_path(characteristics: %w[blackout intrscreen], capacity_max: "100", unit_id: "5")

    # blackout is the only panel characteristic left: intrscreen is promoted,
    # and capacity_max + unit_id are now always-visible filters (out of panel).
    expect(response.body).to include(I18n.t("rooms.filters.applied_count", count: 1))
    expect(response.body).not_to include(I18n.t("rooms.filters.applied_count", count: 2))
  end

  it "renders a humanized card title, unit·floor meta, and a split capacity number" do
    get find_a_room_path

    card = page.find("turbo-frame#find_a_room_results li", match: :first)
    expect(card).to have_text("1401 Mason Hall") # room number + building, not the facility code
    expect(card).to have_text(I18n.t("rooms.row.floor_label", label: "1"))
    expect(card).to have_text("45")
    expect(card).to have_text(I18n.t("rooms.row.seats_label", count: 45))
    # the title itself links to the room page (audit: no disclosure two-step)
    expect(card).to have_link("1401 Mason Hall", href: room_path(room))
    # the four characteristics all fit the emphasized strip — no disclosure
    expect(card).to have_css("ul li span.bg-interactive-subtle")
    expect(card).to have_no_css("details")
  end

  it "shows the top four as an emphasized strip and the rest in a count-labeled disclosure" do
    # All in CARD_TAG_CODES: order = projdigit, lecturecap, doccam, whtbrd, chkbrd, teamtables
    big = classroom(building, "1500", 50,
                    codes: %w[projdigit lecturecap doccam whtbrd chkbrd teamtables], floor: floor)
    big.room_characteristics.find_by(short_code: "projdigit").update!(long_description: "Fixed data projector")

    get find_a_room_path
    card = page.all("turbo-frame#find_a_room_results li").find { |li| li.has_text?("1500") }

    # Strip: exactly the top 4, emphasized.
    strip = card.first("ul")
    expect(strip).to have_css("li span.bg-interactive-subtle", count: 4)

    # Disclosure: the remainder (2), count-labeled, quiet — and NO overlap with the strip.
    summary = card.find("details summary")
    expect(summary).to have_text(I18n.t("rooms.row.more_features", count: 2))
    # Capybara::Node::Simple treats a closed <details>'s content as hidden
    # (no `open` attribute) — same reason other examples in this file target
    # closed-disclosure content with `visible: :all` (see the More-filters
    # panel assertions above).
    details = card.find("details")
    expect(details).to have_css("li span.border-border", count: 2, visible: :all)
    expect(details).to have_no_css("span.bg-interactive-subtle", visible: :all)

    # Popover: the described chip carries its long_description as a tooltip.
    expect(card).to have_text("Fixed data projector")
  end

  # Backlog #7: the applied-count badge lives in the form, OUTSIDE the results
  # frame — a frame-only re-render left it stale. The frame now carries a
  # hidden [data-panel-count] mirror of the same server-side count;
  # filter_form_controller copies it into the [data-panel-badge] holder after
  # each render. Server stays the single source of truth for count + phrasing.
  it "mirrors the panel-applied count inside the results frame for the live badge" do
    get find_a_room_path(characteristics: %w[blackout])

    frame = page.find("turbo-frame#find_a_room_results")
    expect(frame).to have_css("[data-panel-count]", text: I18n.t("rooms.filters.applied_count", count: 1),
                              visible: :all)
    expect(page).to have_css("summary [data-panel-badge]:not([hidden])",
                             text: I18n.t("rooms.filters.applied_count", count: 1))
  end

  it "renders an empty mirror and a hidden badge holder when nothing panel-applied" do
    get find_a_room_path

    expect(page.find("[data-panel-count]", visible: :all).text(:all)).to eq("")
    expect(page).to have_css("summary [data-panel-badge][hidden]", visible: :all)
  end

  # Backlog #8: a curated short name beats humanization — "1018 Chemistry and
  # Dow Willard H Laboratory" wraps on narrow cards; an admin-set short name
  # is the compactness lever (data, not the acronym allowlist in code).
  it "prefers a curated building short name over the humanized vendor name in card titles" do
    building.update!(short_name: "Mason")

    get find_a_room_path

    expect(page).to have_text("1401 Mason")
    expect(page).to have_no_text("1401 Mason Hall")
  end

  it "humanizes ALL-CAPS vendor building names in card titles, keeping campus acronyms" do
    caps = create(:building, workspace: workspace, name: "CHEMISTRY AND DOW WILLARD H LABORATORY")
    acro = create(:building, workspace: workspace, name: "LSA BUILDING")
    classroom(caps, "1300", 500)
    classroom(acro, "2001", 40)

    get find_a_room_path

    expect(page).to have_text("1300 Chemistry and Dow Willard H Laboratory")
    expect(page).to have_text("2001 LSA Building")
  end

  it "falls back to the facility-code title with the building in the meta for numberless rooms" do
    numberless = create(:room, building: building, workspace: workspace,
                        room_number: nil, facility_code: "MASODD")

    get find_a_room_path

    card = page.all("turbo-frame#find_a_room_results li").find { |c| c.has_text?("MASODD") }
    expect(card).to be_present
    expect(card).to have_text("Mason Hall") # building surfaces in the meta line instead
    expect(numberless.room_number).to be_nil
  end

  # Taxonomy phase 3: the promoted movable-seating chip is a MERGED token
  # (movetablet ∪ tablesmov), rendered only when a member code exists in the
  # data; its raw member codes never render their own checkboxes.
  it "renders the merged Movable-seating promoted chip instead of its member codes" do
    get find_a_room_path

    expect(page).to have_css("label[for='characteristics_movableseating']", text: "Movable seating")
    expect(page).to have_css("input[type='checkbox'][name='characteristics[]'][value='movableseating']")
    expect(page).to have_no_css("input[name='characteristics[]'][value='movetablet']", visible: :all)
  end

  it "substitutes one Tiered-or-raked checkbox for its member codes in the panel" do
    classroom(building, "3001", 120, codes: %w[FloorTier])
    classroom(building, "3002", 240, codes: %w[AudSeat])

    get find_a_room_path

    panel = page.find("details#more_filters")
    expect(panel).to have_css("input[type='checkbox'][name='characteristics[]'][value='tieredraked']",
                              visible: :all, count: 1)
    expect(panel).to have_css("label[for='characteristics_tieredraked']", text: "Tiered or raked seating",
                              visible: :all)
    expect(panel).to have_no_css("input[value='floortier']", visible: :all)
    expect(panel).to have_no_css("input[value='audseat']", visible: :all)
  end

  # Taxonomy phase 2: panel groups follow the question-group order from the
  # locale (rooms.filters.group_order), not the builder's alphabetical sort —
  # alphabetically "Recorded…" beats "Show…", so this order proves the lever.
  it "orders panel groups by the question-group locale order, not alphabetically" do
    { "blackout" => "Show & present", "lecturecap" => "Recorded & accessible" }.each do |code, category|
      create(:characteristic_display_rule, workspace: workspace, short_code: code, category_override: category)
    end
    classroom(building, "3003", 25, codes: %w[LectureCap])

    get find_a_room_path

    # category_override values ("Show & present" etc.) are the data-match keys;
    # the rendered legend is the display override ("Presentation").
    legends = page.all("details#more_filters legend", visible: :all).map { |l| l.text(:all) }
    expect(legends.index("Presentation")).to be < legends.index("Recorded & accessible")
  end

  # Filter-label description tooltips: hovering the label (or focusing the
  # checkbox) raises the glossary long_description. Follows UI::Tooltip's own
  # guidance for interactive triggers — aria-describedby on the checkbox
  # itself wired to a role="tooltip" bubble, Esc-dismissable. Rendered ONLY
  # when a description exists; no extra tab stops, no trigger buttons.
  describe "filter label description tooltips" do
    before do
      RoomCharacteristic.find_by!(short_code: "blackout")
        .update!(long_description: "Shades or curtains that fully darken the room.")
      RoomCharacteristic.find_by!(short_code: "whtbrd")
        .update!(long_description: "A wall-mounted dry-erase whiteboard.")
    end

    it "wires described panel checkboxes to hover/focus tooltips via aria-describedby" do
      get find_a_room_path

      panel = page.find("details#more_filters")
      input = panel.find("input[value='blackout']", visible: :all)
      expect(input["aria-describedby"]).to eq("tip_characteristics_blackout")
      expect(panel).to have_css("span#tip_characteristics_blackout[role='tooltip']",
                                text: "Shades or curtains that fully darken the room.", visible: :all)
      # no leftover popover trigger buttons anywhere in the panel
      expect(panel).to have_no_css("button[aria-haspopup='dialog']", visible: :all)
    end

    it "tooltips described promoted chips and skips undescribed labels" do
      get find_a_room_path

      # Select the Popular-features fieldset by its legend — the capacity range
      # is now also a fieldset (and comes first), so :first no longer works.
      popular = page.find("form#find_a_room_form fieldset", text: I18n.t("rooms.filters.popular_legend"))
      expect(popular).to have_css("span[role='tooltip']", text: "wall-mounted dry-erase", visible: :all)
      # intrscreen has no long_description — plain checkbox, no describedby, no bubble
      expect(popular.find("input[value='intrscreen']")["aria-describedby"]).to be_nil
    end
  end

  it "renames vendor group legends through the locale override map" do
    classroom(building, "2002", 30, codes: %w[ethrstud]).room_characteristics
      .first.update!(description: "Ethernet Connection: Students")

    get find_a_room_path

    expect(page).to have_css("details#more_filters legend", text: "Ethernet", visible: :all)
    expect(page).to have_no_css("details#more_filters legend", text: "Ethernet Connection", visible: :all)
  end

  it "hides the workspace shell on the other directory pages too" do
    sidebar = "aside[aria-label='#{I18n.t("workspaces.sidebar.aria_label")}']"

    get buildings_path
    expect(page).to have_no_css(sidebar)

    get filters_glossary_path
    expect(page).to have_no_css(sidebar)
  end

  # Directory pages are public-facing: the workspace shell (sidebar, identity
  # bar, section-nav strip) is workspace-member chrome whose links make no
  # sense to a viewer finding a room (Dave, 2026-07-11).
  it "renders full-width, without the workspace sidebar shell" do
    get find_a_room_path

    expect(page).to have_no_css("aside[aria-label='#{I18n.t("workspaces.sidebar.aria_label")}']")
  end

  describe "saved rooms shortlist" do
    it "puts a save toggle on each card and the Saved count in the header" do
      get find_a_room_path

      card = page.find("turbo-frame#find_a_room_results li", match: :first)
      expect(card).to have_css("form[action='#{saved_rooms_path}']")
      expect(page).to have_css("#saved_rooms_count", text: "0")
      expect(page).to have_link(text: /#{I18n.t("rooms.save.saved_filter")}/)
    end

    it "filters to saved rooms with a removable chip, composing with the form" do
      classroom(building, "1402", 30)
      SavedRoom.create!(user: viewer, room: room, workspace: workspace)

      get find_a_room_path(saved: 1)

      frame = page.find("turbo-frame#find_a_room_results")
      expect(frame).to have_text("1401 Mason Hall")
      expect(frame).to have_no_text("1402 Mason Hall")
      # removable chip drops only the saved filter (the rounded-full pill —
      # the header's "Saved rooms (N)" toggle shares the phrase legitimately)
      chip = frame.find("a.rounded-full", text: I18n.t("rooms.index.summary.saved"))
      expect(chip["href"]).not_to include("saved")
      # the form carries the shortlist view across filter submits
      expect(page).to have_css("form#find_a_room_form input[name='saved']", visible: :all)
    end
  end

  describe "admin inactive views" do
    let(:admin) { membership_with("admin") }

    it "banners the inactive scope with a way back to the active view" do
      sign_in(admin)
      get find_a_room_path(view: "inactive_rooms")

      # role="note", not a live region: persistent context must not re-announce
      # on every filter re-render (UI::Alert's role: override).
      expect(page.find("[role='note']"))
        .to have_text(I18n.t("rooms.index.inactive_view_notice.inactive_rooms"))
      expect(page.find("turbo-frame#find_a_room_results"))
        .to have_link(I18n.t("rooms.index.inactive_view_notice.back_to_active"))
    end

    it "shows no banner on the active view" do
      sign_in(admin)
      get find_a_room_path

      expect(response.body).not_to include(I18n.t("rooms.index.inactive_view_notice.back_to_active"))
    end
  end
end
