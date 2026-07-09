require "rails_helper"

# MiClassrooms Phase 4 Task 8 (Brief §5.3, §14.1): system-spec coverage for
# the admin Buildings index + show — FTS5 search, the hidden-buildings
# toggle, and the axe-AAA both-themes sweep on both pages. Task 9 extends
# this file with the building edit flow. Mirrors spec/system/rooms/
# show_spec.rb's tenancy setup (shared-posture stub + workspace-scoped
# fixtures + sign_in_via_form) and spec/system/rooms/edit_spec.rb's admin
# re-role pattern (Membership.find_by!(...).update!(role: Role.system_default!("admin"))).
RSpec.describe "Buildings", type: :system do
  # Full WCAG 2.2 conformance set (A + AA + AAA) — wcag2aaa alone only runs
  # axe's 3 AAA-only rules and never exercises baseline rules (label,
  # button-name, image-alt, etc.), tagged wcag2a/wcag2aa. See
  # find_a_room_spec.rb.
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2a", "wcag2aa", "wcag2aaa" ] } } }

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

  # MiClassrooms Phase 4 Task 9 (Brief §5.3, §14.1): the admin building edit
  # form — nickname, photo, and per-floor floor-plan management. A second
  # floor with an already-attached PDF plan (plus the building's own photo)
  # is pre-attached before visiting, so the axe sweep below covers the
  # "already attached" branches (photo remove checkbox, PDF plan link +
  # remove checkbox) alongside `floor`'s (label "2") graceful empty state —
  # the same full-branch-coverage reasoning spec/system/rooms/edit_spec.rb
  # uses for the room edit page.
  it "renames the nickname, uploads a floor plan for a floor with none, and is accessible with an existing PDF plan present, in both themes" do
    floor_with_pdf_plan = create(:floor, building: building, workspace: workspace, label: "3")
    floor_with_pdf_plan.plan.attach(io: file_fixture("seating_chart.pdf").open,
                                     filename: "floor-3.pdf", content_type: "application/pdf")
    building.photo.attach(io: file_fixture("room.jpg").open, filename: "mason.jpg", content_type: "image/jpeg")

    visit edit_building_path(building)

    expect(page).to have_selector("h1", text: I18n.t("buildings.edit.title", building: building.display_name))
    # Graceful empty state (D10: a floor plan is optional) — floor "2" has
    # no plan uploaded yet.
    expect(page).to have_content(I18n.t("buildings.edit.no_plan", label: floor.label))
    expect(page).to have_link(I18n.t("buildings.edit.plan_pdf_link", label: floor_with_pdf_plan.label))

    fill_in I18n.t("buildings.edit.nickname_label"), with: "The Mason"
    attach_file I18n.t("buildings.edit.replace_plan_label", label: floor.label), file_fixture("room.jpg").to_s

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    click_button I18n.t("buildings.edit.submit")

    expect(page).to have_current_path(building_path(building))
    expect(page).to have_content(I18n.t("buildings.edit.success"))
    expect(page).to have_selector("h1", text: "Mason Hall (The Mason)")

    expect(building.reload.nickname).to eq("The Mason")
    expect(floor.reload.plan).to be_attached
  end
end
