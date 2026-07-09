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
# Every media slot + two gallery images are pre-attached before visiting, so
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
    room.photo.attach(io: file_fixture("room.jpg").open, filename: "MAS1200.jpg", content_type: "image/jpeg")
    room.panorama.attach(io: file_fixture("room.jpg").open, filename: "MAS1200-360.jpg", content_type: "image/jpeg")
    room.seating_chart.attach(io: file_fixture("seating_chart.pdf").open,
                               filename: "MAS1200-seating.pdf", content_type: "application/pdf")
  end
  let!(:first_image) { create(:room_gallery_image, room: room, workspace: workspace, position: 0) }
  let!(:second_image) { create(:room_gallery_image, room: room, workspace: workspace, position: 1) }

  # Re-role via Membership rather than a factory trait (no :admin trait on
  # :user — see find_a_room_spec.rb's CORRECTION B comment for why).
  let(:admin) do
    user = create(:user)
    Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
    user
  end

  before { sign_in_via_form(admin) }

  it "edits the nickname, uploads a new photo, and reorders the gallery, accessibly in both themes" do
    visit edit_room_path(room)

    expect(page).to have_selector("h1", text: I18n.t("rooms.edit.title", room: room.display_name))

    fill_in I18n.t("rooms.edit.nickname_label"), with: "New Name"
    attach_file I18n.t("rooms.edit.photo_label"), file_fixture("room.jpg").to_s

    # Swap the two gallery images' positions (first ↔ second).
    fill_in I18n.t("rooms.edit.position_label", position: 1), with: "1"
    fill_in I18n.t("rooms.edit.position_label", position: 2), with: "0"

    # Audit the edit page itself in its "filled out, ready to submit" state —
    # every card (curated fields, all three media slots with their
    # current-attachment previews + remove checkboxes, and the gallery with
    # both existing rows plus a blank add row) is on the page at this point.
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    click_button I18n.t("rooms.edit.submit")

    expect(page).to have_current_path(room_path(room))
    expect(page).to have_content(I18n.t("rooms.edit.success"))
    expect(page).to have_selector("h1", text: "New Name")

    expect(room.reload.nickname).to eq("New Name")
    expect(first_image.reload.position).to eq(1)
    expect(second_image.reload.position).to eq(0)
  end
end
