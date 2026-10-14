require "rails_helper"

RSpec.describe "Editor hides a room", type: :system do
  # Matches spec/system/admin/*_axe_spec.rb's AAA-only convention (both
  # themes) rather than find_a_room_spec.rb's fuller A+AA+AAA sweep — this
  # spec mirrors the admin axe specs' shape per the task brief.
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

  # An editor: a plain viewer-role membership (the auto-onboard default under
  # MiClassrooms' shared_join_role, app/lib/tenancy_config.rb) PLUS an
  # EditorAssignment on the room's unit — mirrors
  # spec/requests/room_visibility_spec.rb's editor_for(unit).
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

    uncheck I18n.t("rooms.edit.listed_label"), allow_label_click: true

    accept_confirm(I18n.t("rooms.hide.editor_confirmation")) do
      click_button I18n.t("rooms.edit.submit")
    end

    # RoomsController#hide redirects to policy(@room).show? ? room_path :
    # find_a_room_path — false for the now-hidden room under this editor's
    # grant, so the editor lands on Find a Room, not back on the room.
    expect(page).to have_current_path(find_a_room_path)
    expect(page).to have_content(I18n.t("rooms.hide.success"))

    expect(room.reload).to be_hidden

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on Find a Room (post-hide):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    # Post-hide blindness (phase-4 carryover, Brief §14.1): the editor's very
    # next GET /rooms/:id redirects them straight back out via
    # redirect_inactive_for_non_admins, with the same inactive notice a plain
    # viewer would get — mirrors spec/requests/room_visibility_spec.rb's
    # "post-hide blindness" describe block, as an end-to-end browser proof.
    visit room_path(room)

    expect(page).to have_current_path(find_a_room_path)
    expect(page).to have_content(I18n.t("rooms.inactive_notice"))
  end
end
