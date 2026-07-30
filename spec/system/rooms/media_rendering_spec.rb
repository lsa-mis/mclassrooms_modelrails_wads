require "rails_helper"

# Task 3 (image-metadata-alt-fallback, 2026-07-23): confirms views render
# alt text through Describable#alt_for rather than a hardcoded/derived-in-view
# string — the derived I18n backstop when no alt is authored, and the stored
# `panorama_alt` value once one is. Tenancy/sign-in setup mirrors
# spec/system/rooms/show_spec.rb (shared-posture stub + workspace-scoped
# building/room fixtures + sign_in_via_form).
RSpec.describe "Room media alt rendering", type: :system do
  let!(:workspace) { create(:workspace, slug: "directory", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:building) { create(:building, workspace: workspace) }
  let(:user) { create(:user) }

  it "uses the derived backstop when alt is unauthored, and the stored alt when present" do
    room = create(:room, :with_panorama, building: building, workspace: workspace, panorama_alt: nil)
    sign_in_via_form(user)
    visit room_path(room)

    expect(page).to have_css("img[alt='#{room.alt_for(:panorama)}']") # non-blank derived

    room.update!(panorama_alt: "Lecture hall from the rear doors")
    visit current_path
    expect(page).to have_css("img[alt='Lecture hall from the rear doors']")
  end
end
