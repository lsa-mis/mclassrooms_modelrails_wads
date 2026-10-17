require "rails_helper"

RSpec.describe "Editor hides a room", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  let!(:workspace) { create(:workspace, slug: "editor-hide-room-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:building) { create(:building, name: "Mason Hall", workspace: workspace) }
  let!(:unit) { create(:unit, workspace: workspace, description: "College of Engineering") }
  let!(:room) do
    create(:room, building: building, workspace: workspace, unit: unit,
           room_number: "1200", facility_code: "MAS1200")
  end

  let(:editor) do
    user = create(:user)
    create(:editor_assignment, user: user, unit: unit)
    user
  end

  before { sign_in_via_form(editor) }

  it "confirms with the editor-specific warning, hides the room, and blinds the editor to it afterward" do
    visit edit_room_path(room)

    expect(page).to have_selector("h1", text: room.display_name)
    expect(page).to have_checked_field(I18n.t("rooms.edit.listed_label"), visible: :all)

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on the room page in edit mode (pre-hide):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    accept_confirm(I18n.t("rooms.hide.editor_confirmation")) do
      uncheck I18n.t("rooms.edit.listed_label"), allow_label_click: true
    end

    expect(page).to have_current_path(find_a_room_path)
    expect(page).to have_content(I18n.t("rooms.hide.success"))

    expect(room.reload).to be_hidden

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on Find a Room (post-hide):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    visit room_path(room)

    expect(page).to have_current_path(find_a_room_path)
    expect(page).to have_content(I18n.t("rooms.inactive_notice"))
  end
end
