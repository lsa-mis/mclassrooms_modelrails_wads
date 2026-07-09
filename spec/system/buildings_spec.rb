require "rails_helper"

# MiClassrooms Phase 4 Task 8 (Brief §5.3, §14.1): system-spec coverage for
# the admin Buildings index + show — FTS5 search, the hidden-buildings
# toggle, and the axe-AAA both-themes sweep on both pages. Task 9 extends
# this file with the building edit flow. Mirrors spec/system/rooms/
# show_spec.rb's tenancy setup (shared-posture stub + workspace-scoped
# fixtures + sign_in_via_form) and spec/system/rooms/edit_spec.rb's admin
# re-role pattern (Membership.find_by!(...).update!(role: Role.system_default!("admin"))).
RSpec.describe "Buildings", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  let!(:workspace) { create(:workspace, slug: "directory", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:building) { create(:building, name: "Mason Hall", workspace: workspace, abbreviation: "MH") }
  let!(:floor) { create(:floor, building: building, workspace: workspace, label: "2") }
  let!(:classroom) do
    create(:room, building: building, workspace: workspace, floor: floor, facility_code: "MAS1200")
  end

  let!(:hidden_building) { create(:building, :hidden, workspace: workspace, name: "Old Annex") }
  let!(:hidden_classroom) { create(:room, building: hidden_building, workspace: workspace) }

  # Re-role via Membership rather than a factory trait (no :admin trait on
  # :user — see find_a_room_spec.rb's CORRECTION B comment for why).
  let(:admin) do
    user = create(:user)
    Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
    user
  end

  before { sign_in_via_form(admin) }

  it "searches, toggles hidden buildings, and opens a building show page, accessibly in both themes" do
    visit buildings_path

    expect(page).to have_selector("h1", text: I18n.t("buildings.index.title"))
    expect(page).to have_content("Mason Hall")
    expect(page).not_to have_content("Old Annex")

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    # UI::SwitchComponent's real checkbox is visually `sr-only` (clipped, not
    # display:none) — the same pattern notification_preferences_spec.rb works
    # around by clicking the switch's own visible text <label> (a SEPARATE
    # `<label for=...>` from the switch's clickable-track wrapper label)
    # rather than Capybara's `check`, which requires the checkbox itself to
    # be "visible" under the Playwright driver.
    find("label[for='show_hidden']", text: I18n.t("buildings.index.show_hidden")).click
    expect(page).to have_content("Old Annex")

    # Search narrows to the matching abbreviation prefix; the text field has
    # no auto-submit wiring (only the switch does), so it submits via the
    # form's implicit-submission Enter key, same as a sighted keyboard user.
    fill_in I18n.t("buildings.index.search_label"), with: "MH"
    find_field(I18n.t("buildings.index.search_label")).send_keys(:enter)

    expect(page).to have_content("Mason Hall")
    expect(page).not_to have_content("Old Annex")

    click_link "Mason Hall"

    expect(page).to have_current_path(building_path(building))
    expect(page).to have_selector("h1", text: "Mason Hall")
    expect(page).to have_content("2") # floor label
    expect(page).to have_link(href: floor_plan_room_path(classroom))

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
