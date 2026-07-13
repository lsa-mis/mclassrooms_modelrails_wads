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

  # `let`, not a top-level constant (a bare `AXE_AAA = ...` inside a
  # `describe` block assigns to Object, so a sibling spec file defining the
  # same name raises an "already initialized constant" warning when both
  # load in the same process) — matches spec/system/docs_spec.rb's
  # `axe_options` convention.
  #
  # Full conformance set (A + AA + AAA), not just wcag2aaa: axe's wcag2aaa
  # tag only covers the 3 AAA-only rules (color-contrast-enhanced,
  # identical-links-same-purpose, meta-refresh-no-exceptions). Baseline
  # rules like label/button-name/aria-*/image-alt are tagged wcag2a/wcag2aa
  # and never run under a wcag2aaa-only filter, even though AAA conformance
  # requires A + AA + AAA per WCAG 2.2 §5. Product screens audit the full
  # set; the shared CI after-each hook in playwright_accessibility.rb is
  # left at wcag2aaa only so this fix doesn't blast-radius the template's
  # own specs.
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2a", "wcag2aa", "wcag2aaa" ] } } }

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
    expect(find_field(I18n.t("rooms.filters.search_label")).value).to eq("")
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

      # Sign out the viewer via the user-menu dropdown (same ceremony as
      # spec/system/members_table_spec.rb's mid-example user switch), then
      # sign in as the admin.
      find("#user-menu-button").click
      click_button I18n.t("navigation.sign_out")
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
end
