require "rails_helper"

# MiClassrooms Phase 3 Task 8 (Brief §5.2, §5.4): end-to-end coverage of the
# Find a Room filter round-trip, characteristic AND-semantics, the
# admin-only inactive-rooms toggle, and axe WCAG 2.2 AAA auditing on both the
# viewer and admin renders of the page. The CI after-each hook already audits
# every system spec at wcag2aaa (spec/support/playwright_accessibility.rb) —
# the explicit `axe_violations` assertions below make the same audit
# local-and-loud within these examples too.
RSpec.describe "Find a Room", type: :system do
  include ClassroomBuilders

  # The shared cumulative tag set + rule overrides (backlog #10): 2.0+2.1+2.2
  # at A/AA/AAA plus target-size enablement and the mc-* custom checks that
  # run inside every audit. One source of truth in playwright_accessibility.rb.
  let(:axe_options) { PlaywrightAccessibility::DEFAULT_AXE_OPTIONS.dup }

  # `find_a_room` runs under DirectoryScoped, which sets Current.workspace to
  # the ONE shared workspace resolved by TenancyConfig.shared_workspace_slug,
  # and RoomPolicy::Scope filters every room through `for_current_workspace`.
  # Every building/room below must therefore live in this single shared
  # workspace, or `for_current_workspace` filters them all out and the page
  # renders empty. `let!(:workspace)` + the tenancy stub must precede
  # `sign_in_via_form` in declaration order so `create(:user)`'s
  # `onboard_workspace` after_create callback auto-joins THIS workspace under
  # the :shared posture (mirrors spec/requests/rooms_spec.rb).
  let!(:workspace) { create(:workspace, slug: "directory", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # The :room factory sets `workspace { building.workspace }`, so a room
  # inherits its BUILDING's workspace — every building here is created
  # explicitly `workspace:` the shared workspace above.
  let!(:mason)  { create(:building, name: "Mason Hall", workspace: workspace) }
  let!(:angell) { create(:building, name: "Angell Hall", workspace: workspace) }
  let!(:big)    { classroom(mason, "1200", 80, codes: %w[LectureCap InstrComp]) }
  let!(:small)  { classroom(mason, "2330", 20, codes: %w[LectureCap]) }
  let!(:aud)    { classroom(angell, "3000", 300, codes: %w[InstrComp]) }

  # Auto-joins `workspace` (the :shared posture stubbed above is already
  # active by the time this runs) under TenancyConfig.shared_join_role — a
  # non-admin role, so RoleResolver.for(user).admin? is false and this user
  # never sees the admin-only inactive-rooms views.
  let(:user) { create(:user) }

  before { sign_in_via_form(user) }

  # Cards render room number + building (2026-07 redesign), not facility codes.
  def card_title(room) = "#{room.room_number} #{room.building.name}"

  it "redirects a stale or unknown room link to the directory with a clear message" do
    # 2026-07-15 panel: a shared/stale room link (unknown rmrecnbr) dead-ended on
    # the marketing home with a generic toast; it now lands on Find a Room.
    visit "/rooms/0000000"
    expect(page).to have_current_path(find_a_room_path)
    expect(page).to have_content(I18n.t("rooms.show.not_found"))
  end

  it "filters via Turbo without a full reload and ANDs characteristics" do
    visit find_a_room_path
    expect(page).to have_content(card_title(aud))

    page.execute_script("window.__stayedOnPage = true") # falsy again only after a full reload
    fill_in I18n.t("rooms.filters.search_label"), with: "Mason"
    # The characteristic long tail lives behind the More-filters disclosure
    # (2026-07 redesign) — open it before checking boxes.
    find("#more_filters > summary").click
    check "LectureCap"
    check "InstrComp"

    within "#find_a_room_results" do
      expect(page).to have_content(card_title(big))
      expect(page).to have_no_content(card_title(small)) # LectureCap only — AND semantics
      expect(page).to have_no_content(card_title(aud))   # wrong building + InstrComp only
    end
    # backlog #7: the out-of-frame applied-count badge updates live from the
    # frame's [data-panel-count] mirror — two panel boxes checked, no reload
    expect(page).to have_css("#more_filters summary [data-panel-badge]",
                             text: I18n.t("rooms.filters.applied_count", count: 2))
    expect(page).to have_content(I18n.t("rooms.index.summary.query", value: "Mason"))
    # the persistent out-of-frame announcer carries the fresh count to AT
    # (an in-frame live region replaced by the swap is unreliable — audit)
    expect(page.find("#results_announcer", visible: :all)).to have_text(I18n.t("rooms.index.results_summary", count: 1))
    expect(page.evaluate_script("window.__stayedOnPage")).to be(true)
    expect(page).to have_current_path(/q=Mason/) # turbo_action: advance keeps URL shareable
    expect(axe_violations(axe_options)).to be_empty
  end

  it "round-trips the filter: Clear all restores results AND empties the search box" do
    visit find_a_room_path
    fill_in I18n.t("rooms.filters.search_label"), with: "Mason"

    within "#find_a_room_results" do
      expect(page).to have_content(card_title(big))
      expect(page).to have_no_content(card_title(aud))
    end

    # One clear control (audit): the filter card header link — a full visit,
    # so the fresh render resets both results and form inputs.
    click_link I18n.t("rooms.filters.reset")

    within "#find_a_room_results" do
      expect(page).to have_content(card_title(aud))
    end
    # have_field(with:) RETRIES until the value predicate holds —
    # `find_field(...).value` is a one-shot read that can catch Turbo's cache
    # preview (the stale pre-clear snapshot painted while the fresh page is in
    # flight; the aud assertion above can pass against that same preview,
    # because the cached /find_a_room snapshot is the unfiltered first render).
    # CI screenshot of the old flake shows the settled page WAS correct.
    expect(page).to have_field(I18n.t("rooms.filters.search_label"), with: "")
  end

  it "saves a room from a card, filters to the shortlist, and unsaves" do
    visit find_a_room_path

    within("#save_toggle_room_#{big.id}") { click_button I18n.t("rooms.save.save") }
    # the Turbo Stream flips the toggle and the header count in place
    expect(page).to have_css("#saved_rooms_count", text: "1")
    within("#save_toggle_room_#{big.id}") { expect(page).to have_button(I18n.t("rooms.save.saved")) }

    click_link I18n.t("rooms.save.saved_filter")
    within "#find_a_room_results" do
      expect(page).to have_content(card_title(big))
      expect(page).to have_no_content(card_title(small))
    end

    within("#save_toggle_room_#{big.id}") { click_button I18n.t("rooms.save.saved") }
    expect(page).to have_css("#saved_rooms_count", text: "0")
    expect(axe_violations(axe_options)).to be_empty
  end

  describe "admin inactive-rooms toggle" do
    # A real Classroom-scoped room (facility_code + seat count so
    # Room.classroom matches it) that is simply not in the live feed —
    # excluded from the default view, only reachable via the admin toggle.
    let!(:hidden_classroom) do
      create(:room, building: mason, room_number: "9999", room_type: "Classroom",
             facility_code: "MAS9999", instructional_seat_count: 50, in_feed: false)
    end

    it "hides the toggle from a viewer, and reveals the inactive room to an admin" do
      visit find_a_room_path
      expect(page).to have_no_content(I18n.t("rooms.index.views.inactive_rooms"))

      # CORRECTION B: there is no :admin trait on the :user factory — re-role
      # the auto-joined membership instead (mirrors spec/requests/rooms_spec.rb's
      # `membership_with` pattern). This user auto-joined `workspace` the
      # moment it was created, via the same :shared-posture onboarding.
      admin = create(:user)
      Membership.find_by!(user: admin, workspace: workspace).update!(role: Role.system_default!("admin"))

      # Sign out the viewer via the user-menu dropdown, then sign in as the admin.
      # This page subscribes to the workspace Turbo Stream, and the
      # `Membership#update!` above broadcasts on it (Membership Broadcastable) —
      # the arriving broadcast morphs the authenticated layout / #user-menu
      # subtree. A sign-out click can race that re-render and either raise an
      # ObsoleteNode (Cuprite) OR land on a to-be-replaced node and silently
      # no-op, leaving us on /find-a-room. So: re-navigate for a quiescent page
      # before each attempt (settles the one-shot broadcast and resets menu
      # state), then verify the OUTCOME — retry the whole unit until sign-out
      # actually reaches the sessions page.
      sign_out_attempts = 0
      loop do
        sign_out_attempts += 1
        visit find_a_room_path
        begin
          find("#user-menu-button").click
          within("#user-menu") { click_button I18n.t("navigation.sign_out") }
        rescue Capybara::Cuprite::ObsoleteNode, Ferrum::NodeNotFoundError
          raise if sign_out_attempts > 5
          next
        end
        break if page.has_current_path?(new_session_path, wait: 2)
        raise "sign-out did not reach #{new_session_path} after #{sign_out_attempts} attempts" if sign_out_attempts > 5
      end
      expect(page).to have_current_path(new_session_path)
      sign_in_via_form(admin)

      visit find_a_room_path
      expect(page).to have_content(I18n.t("rooms.index.views.inactive_rooms"))
      within "#find_a_room_results" do
        expect(page).to have_content(card_title(big))
        expect(page).to have_no_content(card_title(hidden_classroom))
      end

      click_link I18n.t("rooms.index.views.inactive_rooms")

      within "#find_a_room_results" do
        expect(page).to have_content(card_title(hidden_classroom))
        expect(page).to have_no_content(card_title(big))
      end
      expect(axe_violations(axe_options)).to be_empty
    end
  end

  describe "tappable card (2026-07-15 panel: the whole card is the tap target)" do
    it "opens the room when a NON-link region of the card (the meta line) is clicked" do
      visit find_a_room_path
      expect(page).to have_content(card_title(big))

      # Click the dead-center of the meta line — a plain <span>, not a link. It
      # navigates only because the title link's `after:` overlay stretches over
      # the whole card (the fix); without the overlay this click does nothing.
      point = cdp_evaluate(<<~JS)
        (() => {
          const li = [...document.querySelectorAll("#find_a_room_results li")]
            .find(el => el.textContent.includes(#{card_title(big).to_json}));
          const meta = li.querySelector("h3 + span");
          const r = meta.getBoundingClientRect();
          return { x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) };
        })()
      JS
      cdp_click_at(point["x"], point["y"])

      expect(page).to have_current_path(room_path(big))
    end
  end

  describe "dark-mode filter controls (2026-07-15 panel)" do
    # The app toggles dark via a `.dark` class but never set `color-scheme`, so
    # the browser drew native checkboxes in its default LIGHT appearance under
    # dark mode — the filter checkboxes read as solid bright-white squares.
    # `:root`/`.dark { color-scheme }` (application.css) fixes it globally.
    it "sets color-scheme: dark so native checkboxes render dark, not bright white" do
      visit find_a_room_path
      ensure_dark_mode
      scheme = cdp_evaluate("getComputedStyle(document.documentElement).colorScheme")
      expect(scheme).to include("dark")
    end
  end
end
