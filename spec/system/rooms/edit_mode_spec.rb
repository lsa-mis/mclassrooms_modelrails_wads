require "rails_helper"

RSpec.describe "Room page view and edit modes", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2a", "wcag2aa", "wcag2aaa" ] } } }

  let!(:workspace) { create(:workspace, slug: "room-modes-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:building) { create(:building, name: "Mason Hall", workspace: workspace) }
  let!(:unit) { create(:unit, workspace: workspace) }
  let!(:room) do
    create(:room, building: building, workspace: workspace, unit: unit,
           room_number: "1200", facility_code: "MAS1200")
  end

  let(:editor) { create(:user).tap { |user| create(:editor_assignment, user: user, unit: unit) } }
  let(:admin) do
    create(:user).tap do |user|
      Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
    end
  end

  it "keeps note controls out of an editor's view mode and brings them back in edit mode" do
    note = create(:note, notable: room, workspace: workspace, author: editor, body: "Lectern mic is in the drawer")
    sign_in_via_form(editor)

    visit room_path(room)

    within("##{ActionView::RecordIdentifier.dom_id(note)}") do
      expect(page).to have_content("Lectern mic is in the drawer")
      expect(page).to have_no_button(I18n.t("notes.actions.delete"))
      expect(page).to have_no_css("summary", text: I18n.t("notes.actions.reply"))
    end

    click_link I18n.t("rooms.show.edit_link")

    expect(page).to have_current_path(edit_room_path(room))
    within("##{ActionView::RecordIdentifier.dom_id(note)}") do
      expect(page).to have_button(I18n.t("notes.actions.delete"))
      expect(page).to have_css("summary", text: I18n.t("notes.actions.reply"))
    end

    click_link I18n.t("rooms.edit.cancel")
    expect(page).to have_current_path(room_path(room))
  end

  it "docks the media strip to the empty band for an admin, accessibly in both themes" do
    sign_in_via_form(admin)
    visit edit_room_path(room)

    within("[data-testid='media-dock']") do
      expect(page).to have_text(I18n.t("rooms.edit.media_strip_none"))
      expect(page).to have_button(I18n.t("rooms.edit.add_panorama"))
    end
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations with the media strip on the empty band:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "shows an admin the hidden overlay and lists and hides the room from the switch in place, accessibly in both themes" do
    room.update!(hidden_at: Time.current, hidden_by: admin)
    sign_in_via_form(admin)

    visit room_path(room)
    expect(page).to have_css("[data-testid='hidden-overlay']", text: I18n.t("rooms.show.hidden_overlay"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations on a hidden room:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    click_link I18n.t("rooms.show.edit_link")
    fill_in I18n.t("rooms.edit.nickname_label"), with: "Not saved yet"
    check I18n.t("rooms.edit.listed_label"), allow_label_click: true

    expect(page).to have_content(I18n.t("rooms.unhide.success"))
    expect(page).to have_field(I18n.t("rooms.edit.nickname_label"), with: "Not saved yet")
    expect(page).to have_no_css("[data-testid='hidden-overlay']")
    expect(page).to have_current_path(edit_room_path(room))
    expect(room.reload).not_to be_hidden

    dismiss_confirm(I18n.t("rooms.hide.admin_confirmation")) do
      uncheck I18n.t("rooms.edit.listed_label"), allow_label_click: true
    end
    expect(page).to have_checked_field(I18n.t("rooms.edit.listed_label"), visible: :all)
    expect(room.reload).not_to be_hidden

    accept_confirm(I18n.t("rooms.hide.admin_confirmation")) do
      uncheck I18n.t("rooms.edit.listed_label"), allow_label_click: true
    end
    expect(page).to have_content(I18n.t("rooms.hide.success"))
    expect(page).to have_css("[data-testid='hidden-overlay']")
    expect(page).to have_unchecked_field(I18n.t("rooms.edit.listed_label"), visible: :all)
    expect(page.evaluate_script("document.activeElement.id")).to eq("room_listed")
    expect(room.reload).to be_hidden
  end
end
