# frozen_string_literal: true

require "rails_helper"

# Two-mode media stage (planning/specs/2026-08-07-room-media-stage-photos-design.md).
# State table: pano+photos → pano default with chip; photos-only → photo mode,
# no chip; pano-only → no chip (covered by existing pano specs in show_spec.rb).
# Tenancy/attachment setup mirrors spec/system/rooms/media_rendering_spec.rb
# and spec/system/rooms/show_spec.rb (shared-posture stub + workspace-scoped
# building/room fixtures + sign_in_via_form).
RSpec.describe "Room media stage", type: :system do
  let!(:workspace) { create(:workspace, slug: "directory", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:building) { create(:building, workspace: workspace) }
  let(:user) { create(:user) }

  # Scopes the axe sweep to the full WCAG 2.2 conformance set (A + AA + AAA),
  # same pattern as show_spec.rb.
  let(:axe_options) { PlaywrightAccessibility::DEFAULT_AXE_OPTIONS.dup }

  # count() `:media_asset` rows on `room`, position 1..count in creation
  # order so MediaAsset.ordered (position, id) yields a deterministic index.
  # `descriptions` maps a 0-based gallery index to an image_description
  # (caption) — assets not named there keep the factory's blank description,
  # which is what exercises the "count-only badge" behavior.
  def create_media_assets(room, count, descriptions: {})
    count.times do |i|
      create(:media_asset, owner: room, workspace: workspace, position: i + 1,
             image_description: descriptions[i])
    end
  end

  it "defaults to pano mode with the photos chip when both media exist" do
    room = create(:room, :with_panorama, building: building, workspace: workspace)
    create_media_assets(room, 2)
    sign_in_via_form(user)
    visit room_path(room)

    expect(page).to have_css("[data-testid='media-chip']", visible: :visible)
    expect(page).to have_css("[data-testid='photo-frame']", visible: :hidden)
    expect(page).to have_css("#room_panorama_stage img", visible: :visible)
  end

  it "chip toggles to photo mode and back, and the pano element is never re-created" do
    room = create(:room, :with_panorama, building: building, workspace: workspace)
    create_media_assets(room, 2)
    sign_in_via_form(user)
    visit room_path(room)

    # Stamp the permanent pano element before ever toggling modes — if the
    # controller (or a Turbo morph) ever recreated it instead of merely
    # hiding it, this custom dataset value would be wiped.
    page.execute_script("document.getElementById('room_panorama_stage').dataset.probe = 'alive'")

    click_button I18n.t("rooms.show.view_photos", count: 2)
    expect(page).to have_css("[data-testid='photo-frame']", visible: :visible)
    expect(page).to have_css("#room_panorama_stage", visible: :hidden)
    expect(page).to have_no_css("[data-testid='media-chip']", visible: :visible)
    expect(page).to have_button(I18n.t("rooms.show.back_to_panorama"))

    click_button I18n.t("rooms.show.back_to_panorama")
    expect(page).to have_css("#room_panorama_stage", visible: :visible)
    expect(page).to have_css("[data-testid='photo-frame']", visible: :hidden)
    expect(page).to have_css("[data-testid='media-chip']", visible: :visible)

    expect(page.evaluate_script("document.getElementById('room_panorama_stage').dataset.probe")).to eq("alive")
  end

  it "arrows and keyboard cycle photos with wraparound and update the badge" do
    # Photos-only room: starts in photo mode already, so this example can
    # focus purely on prev/next + keyboard behavior (mode toggling is
    # covered above).
    room = create(:room, building: building, workspace: workspace)
    create_media_assets(room, 3, descriptions: { 1 => "Front row seating" })
    sign_in_via_form(user)
    visit room_path(room)

    next_button = find("button[aria-label='#{I18n.t('rooms.show.next_photo')}']")
    next_button.click
    expect(find("[data-testid='photo-badge']").text)
      .to eq("Front row seating · #{I18n.t('rooms.show.photo_badge_position', n: 2, total: 3)}")

    # Two lefts from index 1 (the still-focused next-button's keydown bubbles
    # to the frame's keydown.left listener): 1 -> 0 -> wraps to 2 (last).
    # Dispatched via CDP (like the Escape presses elsewhere in this suite) —
    # Capybara/Cuprite's `send_keys` proved unreliable for repeated presses
    # against a Stimulus keydown action here.
    cdp_press("ArrowLeft")
    cdp_press("ArrowLeft")
    expect(find("[data-testid='photo-badge']").text)
      .to eq(I18n.t("rooms.show.photo_badge_position", n: 3, total: 3))
  end

  it "clicking the photo opens the popout at the same index and navigation syncs back" do
    room = create(:room, building: building, workspace: workspace)
    create_media_assets(room, 3)
    sign_in_via_form(user)
    visit room_path(room)

    next_button = find("button[aria-label='#{I18n.t('rooms.show.next_photo')}']")
    next_button.click # advance to photo 2 (index 1)

    find("[data-media-stage-target='slide']:not([hidden])").click
    dialog = find("dialog[open]")
    expect(dialog).to have_css("[data-gallery-target='count']", text: "2 / 3")

    dialog.find("[data-action='click->gallery#next']").click
    expect(dialog).to have_css("[data-gallery-target='count']", text: "3 / 3")

    cdp_press("Escape")
    expect(page).to have_no_css("dialog[open]")
    # gallery:navigated synced the frame's index back while the dialog was
    # still open; closing it must not undo that sync.
    expect(find("[data-testid='photo-badge']").text)
      .to eq(I18n.t("rooms.show.photo_badge_position", n: 3, total: 3))
  end

  it "starts in photo mode without a chip when the room has no panorama" do
    room = create(:room, building: building, workspace: workspace)
    create_media_assets(room, 2)
    sign_in_via_form(user)
    visit room_path(room)

    expect(page).to have_css("[data-testid='photo-frame']", visible: :visible)
    expect(page).to have_no_css("[data-testid='media-chip']")
    # Not merely hidden — never rendered at all when there is no panorama.
    expect(page).to have_no_css("#room_panorama_stage", visible: :all)
  end

  it "shows count-only badge when the caption is blank" do
    room = create(:room, building: building, workspace: workspace)
    create_media_assets(room, 2) # no descriptions -> every caption is blank
    sign_in_via_form(user)
    visit room_path(room)

    expect(find("[data-testid='photo-badge']").text)
      .to eq(I18n.t("rooms.show.photo_badge_position", n: 1, total: 2))
  end

  it "is axe-clean in photo mode and with the popout open" do
    room = create(:room, :with_panorama, building: building, workspace: workspace)
    create_media_assets(room, 2)
    sign_in_via_form(user)
    visit room_path(room)
    ensure_light_mode

    click_button I18n.t("rooms.show.view_photos", count: 2)
    expect(axe_violations(axe_options)).to be_empty,
      "Accessibility violations in photo mode:\n#{axe_violations(axe_options).join("\n")}"

    find("[data-media-stage-target='slide']:not([hidden])").click
    expect(page).to have_css("dialog[open]")
    expect(axe_violations(axe_options)).to be_empty,
      "Accessibility violations with the popout open:\n#{axe_violations(axe_options).join("\n")}"
  end
end
