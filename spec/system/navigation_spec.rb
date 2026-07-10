require "rails_helper"

# Product navigation phase: wires the phase 1-5 features into the site
# chrome so the app is actually browsable. Covers three previously-missing
# entry points:
#   1. "Find a Room" — a header link for every signed-in user (shared/_header).
#   2. The Admin menu — previously a genuinely empty disclosure
#      (shared/_admin_nav), now populated with the admin section links.
#   3. The building breadcrumb on a room's show page (rooms/_header) — Phase
#      5's realty visibility model (BuildingPolicy#show?) opens a non-hidden
#      building's detail page to viewers, not just admins, so the crumb is a
#      real link for anyone who may view that building.
#
# Tenancy setup mirrors spec/system/find_a_room_spec.rb and
# spec/system/rooms/show_spec.rb: stub the :shared onboarding posture to a
# real workspace so `create(:user)`'s `onboard_workspace` after_create
# callback auto-joins it, and every building/room fixture lives in that same
# workspace (Tenanted scoping would otherwise filter them out).
RSpec.describe "Product navigation", type: :system do
  include ClassroomBuilders

  # Full WCAG 2.2 conformance set (A + AA + AAA) — matches the product-screen
  # convention in find_a_room_spec.rb / rooms/show_spec.rb: the wcag2aaa tag
  # alone only exercises axe's 3 AAA-only rules, not the baseline
  # label/button-name/aria-* rules tagged wcag2a/wcag2aa that AAA conformance
  # (WCAG 2.2 §5) still requires.
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2a", "wcag2aa", "wcag2aaa" ] } } }

  let!(:workspace) { create(:workspace, slug: "directory", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  def promote_to_admin!(user)
    Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
  end

  describe "Find a Room entry point" do
    let(:user) { create(:user) }

    before { sign_in_via_form(user) }

    it "shows a Find a Room link for a plain viewer that navigates to the directory" do
      visit root_path
      # Scoped to "header", not "header nav" — shared/_admin_nav renders its
      # own nested <nav aria-label="Admin navigation">, so an admin-visible
      # page has 2 <nav> descendants of <header> (pre-existing structure);
      # "header nav" is ambiguous whenever that partial renders.
      within("header") do
        expect(page).to have_link(I18n.t("navigation.find_a_room"), href: find_a_room_path)
        click_link I18n.t("navigation.find_a_room")
      end
      expect(page).to have_current_path(find_a_room_path)
    end

    it "does NOT show the Admin menu for a plain viewer" do
      visit root_path
      within("header") do
        expect(page).to have_no_text(I18n.t("navigation.admin.label"))
      end
    end
  end

  describe "Admin menu" do
    let(:user) { create(:user) }

    before do
      sign_in_via_form(user)
      promote_to_admin!(user)
      visit root_path
    end

    it "also shows the Find a Room link for an admin" do
      within("header") do
        expect(page).to have_link(I18n.t("navigation.find_a_room"), href: find_a_room_path)
      end
    end

    it "opens to reveal every admin section link at its exact href, and each navigates" do
      click_button I18n.t("navigation.admin.label")

      within "#admin-nav-panel" do
        expect(page).to have_link(I18n.t("navigation.admin.buildings"), href: buildings_path)
        expect(page).to have_link(I18n.t("navigation.admin.announcements"), href: admin_announcements_path)
        expect(page).to have_link(I18n.t("navigation.admin.editor_assignments"), href: admin_editor_assignments_path)
        expect(page).to have_link(I18n.t("navigation.admin.bulk_upload"), href: new_admin_bulk_upload_path)
        expect(page).to have_link(I18n.t("navigation.admin.characteristic_display_rules"),
                                   href: admin_characteristic_display_rules_path)
        expect(page).to have_link(I18n.t("navigation.admin.unit_display_names"), href: admin_unit_display_names_path)
        expect(page).to have_link(I18n.t("navigation.admin.sync_scope_rules"), href: admin_sync_scope_rules_path)
      end

      click_link I18n.t("navigation.admin.announcements")
      expect(page).to have_current_path(admin_announcements_path)
    end
  end

  describe "Building breadcrumb on a room's show page" do
    let!(:building) { create(:building, name: "Mason Hall", workspace: workspace) }
    let!(:room) do
      create(:room, building: building, workspace: workspace, room_number: "1200",
             facility_code: "MAS1200", instructional_seat_count: 80)
    end
    let(:user) { create(:user) }

    before { sign_in_via_form(user) }

    it "shows the building name as a real link for a viewer when the building is not hidden" do
      visit room_path(room)
      expect(page).to have_link(building.display_name, href: building_path(building))
    end
  end

  describe "accessibility (axe AAA, both themes)" do
    let(:user) { create(:user) }

    it "the header passes for a plain viewer" do
      sign_in_via_form(user)
      visit root_path

      expect(axe_clean_in_both_themes?(axe_options, include: "header")).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options, include: "header").join("\n")}"
    end

    it "the header passes for an admin with the Admin menu OPEN" do
      sign_in_via_form(user)
      promote_to_admin!(user)
      visit root_path

      click_button I18n.t("navigation.admin.label")
      expect(page).to have_css("#admin-nav-panel:not(.hidden)")

      expect(axe_clean_in_both_themes?(axe_options, include: "header")).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options, include: "header").join("\n")}"
    end
  end
end
