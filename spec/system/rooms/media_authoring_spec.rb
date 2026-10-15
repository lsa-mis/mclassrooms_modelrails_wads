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

    expect(page).to have_content(I18n.t("rooms.edit.panorama_saved"))
    expect(page).to have_current_path(edit_room_path(room))

    room.reload
    expect(room.alt_status_for(:panorama)).to eq(:authored)
    expect(room.description_for(:panorama)).to eq("Two aisles; step-free front row.")
  end

  it "removes a photo from the photos dialog after confirming, and stays in the dialog, accessibly in both themes" do
    axe_options = { runOnly: { type: "tag", values: [ "wcag2a", "wcag2aa", "wcag2aaa" ] } }
    room = create(:room, building: building, workspace: workspace)
    create(:media_asset, owner: room, workspace: workspace, position: 1)
    doomed = create(:media_asset, owner: room, workspace: workspace, position: 2)

    visit edit_room_path(room)
    click_button I18n.t("rooms.edit.manage_photos", count: 2)

    expect(page).to have_css("dialog#gallery-editor[open]")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations with the photos dialog open:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    accept_confirm(I18n.t("rooms.edit.remove_photo_confirm", position: 2, room: room.display_name)) do
      within("dialog#gallery-editor") { click_button "#{I18n.t("rooms.edit.remove_photo")} 2" }
    end

    expect(page).to have_css("dialog#gallery-editor[open]")
    expect(page).to have_current_path(edit_room_path(room, open: "gallery"))
    expect(MediaAsset.exists?(doomed.id)).to be(false)
    expect(room.gallery.count).to eq(1)

    within("dialog#gallery-editor") { click_button I18n.t("rooms.edit.cancel") }
    expect(page).to have_no_css("dialog#gallery-editor[open]")
    expect(page.evaluate_script("document.activeElement.textContent.trim()"))
      .to eq(I18n.t("rooms.edit.manage_photos", count: 1))
  end

  it "previews only a chosen file it can show, and brings back the saved image when the choice is cleared" do
    room = create(:room, building: building, workspace: workspace)
    room.seating_chart.attach(io: file_fixture("room.jpg").open, filename: "chart.jpg", content_type: "image/jpeg")
    label = I18n.t("rooms.edit.upload_new_seating_chart")

    visit edit_room_path(room)
    find("[data-testid='seating-chart-edit']").click

    within("dialog#seating-chart-editor") do
      saved = find("[data-testid='media-preview'] img")[:src]

      attach_file label, browser_upload_fixture("room.jpg")
      expect(find("[data-testid='media-preview'] img")[:src]).to start_with("blob:")

      attach_file label, browser_upload_fixture("seating_chart.pdf")
      expect(page).to have_no_css("[data-testid='media-preview']")

      page.execute_script(<<~JS)
        const input = document.getElementById("room_seating_chart")
        input.value = ""
        input.dispatchEvent(new Event("change", { bubbles: true }))
      JS
      expect(find("[data-testid='media-preview'] img")[:src]).to eq(saved)
    end
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
