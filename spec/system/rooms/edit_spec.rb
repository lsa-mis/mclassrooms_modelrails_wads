require "rails_helper"

# MiClassrooms Phase 4 Task 7 (Brief §5.3, §14.1): system-spec coverage for
# the admin room edit surface — curated fields, media replace, and gallery
# reorder, all routed through Curation::Apply per the request specs'
# contract (spec/requests/rooms_spec.rb). Mirrors
# spec/system/rooms/show_spec.rb's tenancy setup (shared-posture stub +
# workspace-scoped fixtures + sign_in_via_form) and
# spec/system/find_a_room_spec.rb's admin re-role pattern
# (Membership.find_by!(...).update!(role: Role.system_default!("admin"))).
#
# Both media slots + two gallery photos are pre-attached before visiting, so
# the page renders its richer "already attached" branches (current-attachment
# figure + remove_* checkbox per slot, both gallery rows editable) for the
# axe sweep below — the same full-branch-coverage reasoning show_spec.rb
# uses for the room show page.
RSpec.describe "Room edit", type: :system do
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

  let!(:building) { create(:building, name: "Mason Hall", workspace: workspace) }
  let!(:room) do
    create(:room, building: building, workspace: workspace, room_number: "1200",
           facility_code: "MAS1200", nickname: "Old Name")
  end

  before do
    room.panorama.attach(io: file_fixture("room.jpg").open, filename: "MAS1200-360.jpg", content_type: "image/jpeg")
    room.seating_chart.attach(io: file_fixture("seating_chart.pdf").open,
                               filename: "MAS1200-seating.pdf", content_type: "application/pdf")
  end
  let!(:first_image) { create(:media_asset, owner: room, workspace: workspace, position: 1) }
  let!(:second_image) { create(:media_asset, owner: room, workspace: workspace, position: 2) }

  # Re-role via Membership rather than a factory trait (no :admin trait on
  # :user — see find_a_room_spec.rb's CORRECTION B comment for why).
  let(:admin) do
    user = create(:user)
    Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
    user
  end

  before { sign_in_via_form(admin) }

  it "edits the nickname in place on the room page, accessibly in both themes" do
    visit edit_room_path(room)

    expect(page).to have_selector("h1", text: room.display_name)
    expect(page).to have_css("[data-room-mode='edit']")

    fill_in I18n.t("rooms.edit.nickname_label"), with: "New Name"

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    click_button I18n.t("rooms.edit.submit")

    expect(page).to have_current_path(room_path(room))
    expect(page).to have_content(I18n.t("rooms.edit.success"))
    expect(page).to have_selector("h1", text: "New Name")
    expect(room.reload.nickname).to eq("New Name")
  end

  it "replaces the panorama from its dialog in place, accessibly in both themes" do
    visit edit_room_path(room)
    original_preview = find("#room_panorama_stage img", visible: :all)[:src]

    click_button I18n.t("rooms.edit.edit_panorama")

    within("dialog#panorama-editor") do
      attach_file I18n.t("rooms.edit.upload_new_panorama"), browser_upload_fixture("room.jpg")
      expect(find("[data-testid='media-preview'] img")[:src]).to start_with("blob:")
    end

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations with the panorama dialog open:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    within("dialog#panorama-editor") { click_button I18n.t("rooms.edit.save_media") }

    expect(page).to have_content(I18n.t("rooms.edit.panorama_saved"))
    expect(page).to have_no_css("dialog#panorama-editor[open]")
    expect(page).to have_current_path(edit_room_path(room))
    expect(find("#room_panorama_stage img", visible: :all)[:src]).not_to eq(original_preview)
    expect(page.evaluate_script("document.activeElement.textContent").squish).to eq(I18n.t("rooms.edit.edit_panorama"))

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations after the in-place save:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "reorders the gallery from the photos sheet" do
    visit edit_room_path(room)

    click_button I18n.t("rooms.edit.manage_photos", count: 2)

    within("dialog#gallery-editor") do
      fill_in I18n.t("rooms.edit.position_label", position: 1), with: "2"
      fill_in I18n.t("rooms.edit.position_label", position: 2), with: "1"
      click_button I18n.t("rooms.edit.save_media")
    end

    expect(page).to have_content(I18n.t("rooms.edit.gallery_saved"))
    expect(page).to have_current_path(edit_room_path(room))
    expect(first_image.reload.position).to eq(2)
    expect(second_image.reload.position).to eq(1)
  end
end
