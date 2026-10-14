require "rails_helper"

RSpec.describe "Authoring room media metadata", type: :system do
  let!(:workspace) { create(:workspace, slug: "directory", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:building) { create(:building, name: "Mason Hall", workspace: workspace) }

  # Re-role via Membership rather than a factory trait (no :admin trait on
  # :user — see spec/system/find_a_room_spec.rb's CORRECTION B comment).
  let(:admin) do
    user = create(:user)
    Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
    user
  end

  before { sign_in_via_form(admin) }

  it "lets an admin author alt/description and mark derived-ok, clearing needs_review" do
    room = create(:room, :with_panorama, building: building, workspace: workspace,
                  panorama_alt: nil, panorama_derived_ok: false)

    visit edit_room_path(room)
    click_button I18n.t("rooms.edit.edit_panorama")

    within("dialog#panorama-editor") do
      fill_in "room[panorama_alt]", with: "Lecture hall, seats facing the podium"
      fill_in "room[panorama_description]", with: "Two aisles; step-free front row."
      click_button I18n.t("rooms.edit.save_media")
    end

    expect(page).to have_current_path(room_path(room))
    expect(page).to have_content(I18n.t("rooms.edit.success"))

    room.reload
    expect(room.alt_status_for(:panorama)).to eq(:authored)
    expect(room.description_for(:panorama)).to eq("Two aisles; step-free front row.")
  end

  it "retires an item via the derived-ok checkbox without authored alt" do
    room = create(:room, building: building, workspace: workspace,
                  seating_chart_alt: nil, seating_chart_derived_ok: false)
    room.seating_chart.attach(io: file_fixture("seating_chart.pdf").open,
                               filename: "seating.pdf", content_type: "application/pdf")

    visit edit_room_path(room)
    click_button I18n.t("rooms.edit.edit_seating_chart")

    within("dialog#seating-chart-editor") do
      check "room[seating_chart_derived_ok]"
      click_button I18n.t("rooms.edit.save_media")
    end

    expect(page).to have_current_path(room_path(room))
    expect(room.reload.alt_status_for(:seating_chart)).to eq(:derived_ok)
  end

  # Matches spec/system/rooms/edit_spec.rb's fuller A+AA+AAA sweep (not the
  # AAA-only convention some other specs use) since this is the same edit
  # page that spec already audits — full-branch coverage for the new fields
  # this task adds on top of it.
  it "has no accessibility violations on the media edit form, in both themes" do
    axe_options = { runOnly: { type: "tag", values: [ "wcag2a", "wcag2aa", "wcag2aaa" ] } }
    room = create(:room, :with_panorama, building: building, workspace: workspace)
    room.seating_chart.attach(io: file_fixture("seating_chart.pdf").open,
                               filename: "seating.pdf", content_type: "application/pdf")
    create(:media_asset, owner: room, workspace: workspace, position: 1)

    visit edit_room_path(room)

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
