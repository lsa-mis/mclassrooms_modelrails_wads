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

  # Regression coverage for two bugs caught in review then left unprotected
  # (the covering spec was written, then deleted before commit):
  #   1. notes/_list.html.erb's `:rich_text_body` eager-load — without it,
  #      rendering more than one note fires a query per note on the
  #      has_rich_text association, which trips Bullet.raise (enabled below
  #      via the app's `Bullet.raise = true` test config) as an N+1.
  #   2. notes/_note.html.erb's `<%= note.body %>` — using `note.body` (no
  #      `<%=`) swallows the RichText output; asserting the rendered body
  #      text below fails if that regresses.
  # One alert + one plain root note on the room, one note on the building —
  # three notes total, enough to trip the N+1 if the preload regresses.
  let!(:room_alert_note) do
    create(:note, :alert, notable: room, workspace: workspace, author: user,
           body: "Projector bulb needs replacement")
  end
  let!(:room_plain_note) do
    create(:note, notable: room, workspace: workspace, author: user,
           body: "Room was repainted last spring")
  end
  let!(:building_note) do
    create(:note, notable: building, workspace: workspace, author: user,
           body: "Building elevator under maintenance")
  end

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

    # Room notes (own alert + own plain) and the building's note all render
    # their RichText body content — protects the swallowed-body fix. Bullet
    # is active in test (raises on N+1), so rendering all three notes here
    # also protects the :rich_text_body eager-load fix implicitly: this
    # example would raise Bullet::Notification::UnoptimizedQueryError instead
    # of reaching these assertions if the preload regressed.
    expect(page).to have_content(room_alert_note.body.to_plain_text)
    expect(page).to have_content(room_plain_note.body.to_plain_text)
    expect(page).to have_content(building_note.body.to_plain_text)

    click_button I18n.t("rooms.show.share.button")
    expect(page).to have_content(I18n.t("rooms.show.share.copied"))
  end
end
