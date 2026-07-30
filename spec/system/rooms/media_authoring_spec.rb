require "rails_helper"

# MiClassrooms Task 4 (image metadata, Brief §5.2/design spec
# 2026-07-23-mclassrooms-image-metadata-alt-fallback): the admin authoring UI
# on top of Describable (columns + resolvers, Tasks 1-3) — alt/description
# text fields plus a "the auto-generated alt is fine here" checkbox per
# media slot, so `alt_status_for(slot)` can report :authored/:derived_ok
# instead of :needs_review. Mirrors spec/system/rooms/edit_spec.rb's tenancy
# setup (shared-posture stub + workspace-scoped fixtures + sign_in_via_form)
# and its admin re-role pattern (Membership.find_by!(...).update!(role:
# Role.system_default!("admin"))).
#
# DEVIATION from this task's brief: the brief's snippet sketches
# `sign_in_editor_for(room)` as "the existing editor-auth helper used by
# other rooms/edit specs" — no such helper, and no such spec, exists.
# RoomPolicy#manage_media? is admin-only (even though #update?/#edit? admit
# a unit editor per Phase 5 Task 3), and rooms/edit.html.erb only renders
# rooms/edit/_media_sections — where every alt/description/derived_ok field
# lives — when `policy(@room).manage_media?` is true; an editor instead sees
# the media_admin_only_hint banner with none of these fields at all (proven
# by spec/requests/rooms_update_spec.rb's "renders the curated fields and
# the media-admin-only hint, but not the media inputs" spec). So this spec
# signs in as an admin, exactly like spec/system/rooms/edit_spec.rb, rather
# than the brief's placeholder editor helper.
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

    fill_in "room[panorama_alt]", with: "Lecture hall, seats facing the podium"
    fill_in "room[panorama_description]", with: "Two aisles; step-free front row."
    click_button I18n.t("rooms.edit.submit")

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

    check "room[seating_chart_derived_ok]"
    click_button I18n.t("rooms.edit.submit")

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
    room.photo.attach(io: file_fixture("room.jpg").open, filename: "photo.jpg", content_type: "image/jpeg")
    room.seating_chart.attach(io: file_fixture("seating_chart.pdf").open,
                               filename: "seating.pdf", content_type: "application/pdf")
    create(:room_gallery_image, room: room, workspace: workspace, position: 0)

    visit edit_room_path(room)

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
