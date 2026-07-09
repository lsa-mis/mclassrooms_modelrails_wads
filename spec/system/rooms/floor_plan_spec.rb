require "rails_helper"

# MiClassrooms Phase 4 Task 6 (Brief §5.3): full system-spec coverage for the
# floor-plan view — the plan-image case (breadcrumb, h1, plan figure,
# same-floor room list with the current-room badge) and the graceful
# empty-state case (D10: no plan uploaded yet), each swept for axe-AAA in
# both themes. Mirrors spec/system/rooms/show_spec.rb's tenancy setup:
# shared-posture stub + workspace-scoped building/room fixtures +
# sign_in_via_form.
RSpec.describe "Room floor plan", type: :system do
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
  let!(:other_room_on_floor) do
    create(:room, building: building, workspace: workspace, floor: floor, room_number: "1201",
           facility_code: "MAS1201", instructional_seat_count: 30)
  end

  # Auto-joins `workspace` (the :shared posture stubbed above is already
  # active by the time this runs) under TenancyConfig.shared_join_role.
  let(:user) { create(:user) }

  before { sign_in_via_form(user) }

  # Scoped to WCAG 2.2 AAA (matches show_spec.rb / static_pages_spec.rb) —
  # unscoped axe.run also picks up best-practice-only rules against
  # shared/_toasts.html.erb's always-present, currently-empty toast
  # containers, which is a pre-existing, page-independent condition and not
  # a WCAG failure.
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  it "renders the plan image, breadcrumb, and same-floor room list accessibly in both themes" do
    floor.plan.attach(io: file_fixture("room.jpg").open,
                       filename: "mason-2.jpg", content_type: "image/jpeg")

    visit floor_plan_room_path(room)

    expect(page).to have_selector(
      "h1", text: I18n.t("rooms.floor_plan.title", building: building.display_name, floor: floor.label)
    )
    expect(page).to have_link(room.display_name, href: room_path(room))
    expect(page).to have_content(other_room_on_floor.display_name)
    expect(page).to have_content(I18n.t("rooms.floor_plan.current_room"))

    expect(page).to have_css("figure img")
    plan_alt = I18n.t("rooms.floor_plan.plan_alt", building: building.display_name, floor: floor.label)
    expect(page.find("figure img")["alt"]).to eq(plan_alt)

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "renders the no-plan empty state accessibly in both themes" do
    visit floor_plan_room_path(room)

    expect(page).to have_no_css("figure img")
    expect(page).to have_content(I18n.t("rooms.floor_plan.no_plan"))
    expect(page).to have_content(other_room_on_floor.display_name)

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
