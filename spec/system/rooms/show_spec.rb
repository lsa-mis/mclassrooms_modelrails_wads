require "rails_helper"

# MiClassrooms Phase 4 Task 4 (Brief §5.3): starter system-spec coverage for
# the room detail page. Task 5 completes this file with the media suite
# (photo/gallery/panorama/seating-chart) plus the axe-AAA both-themes sweep —
# this task only asserts the HTML that already renders without media: the
# h1, the capacity line, a characteristic chip's visible label, the "Not
# Available" contact fallback, and the share confirmation text. Mirrors
# spec/system/find_a_room_spec.rb's tenancy setup: shared-posture stub +
# workspace-scoped building/room fixtures + sign_in_via_form.
RSpec.describe "Room show", type: :system do
  let!(:workspace) { create(:workspace, slug: "directory", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:building) { create(:building, name: "Mason Hall", workspace: workspace) }
  let!(:room) do
    create(:room, building: building, workspace: workspace, room_number: "1200",
           facility_code: "MAS1200", instructional_seat_count: 80, ada_seat_count: 2)
  end

  # Normalization-stable short_code (RoomCharacteristic#short_code is NOT
  # model-normalized, unlike CharacteristicDisplayRule#short_code, which
  # CodeNormalizer strips non-alphanumerics from) — "projector" survives
  # normalization unchanged, so the presenter's icon-key join hits and the
  # chip renders a real icon instead of falling back to FALLBACK_ICON.
  let!(:room_characteristic) do
    create(:room_characteristic, room: room, workspace: workspace,
           short_code: "projector", description: "Media: Projector")
  end

  before do
    create(:characteristic_display_rule, workspace: workspace,
           short_code: "projector", icon_key: "computer_desktop")
  end

  # Auto-joins `workspace` (the :shared posture stubbed above is already
  # active by the time this runs) under TenancyConfig.shared_join_role — a
  # non-admin role, matching the room's viewer-facing render (no inactive
  # banner, no admin-only affordances).
  let(:user) { create(:user) }

  before { sign_in_via_form(user) }

  it "renders the header, a characteristic chip, a contact fallback, and the share confirmation" do
    visit room_path(room)

    expect(page).to have_selector("h1", text: room.display_name)
    expect(page).to have_content(
      I18n.t("rooms.show.capacity", students: room.instructional_seat_count, ada: room.ada_seat_count)
    )
    expect(page).to have_content("Projector")

    # room.room_contact is nil — every contact field falls back to
    # "Not available" rather than raising on a missing association.
    expect(page).to have_content(I18n.t("rooms.show.not_available"))

    click_button I18n.t("rooms.show.share.button")
    expect(page).to have_content(I18n.t("rooms.show.share.copied"))
  end
end
