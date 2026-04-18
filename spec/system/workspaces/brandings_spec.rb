require "rails_helper"

RSpec.describe "Workspace branding — identity picker", type: :system do
  let(:user) { create(:user) }
  # User#after_create :create_personal_workspace guarantees a workspace exists.
  let(:workspace) { user.workspaces.first }
  let(:logo_fixture) { Rails.root.join("spec/fixtures/files/avatar.png") }

  before do
    sign_in_via_form(user)
    visit edit_workspace_branding_path(workspace)
  end

  describe "logo upload flow" do
    it "uploads, crops, and saves a workspace logo via the JS saveCrop path" do
      open_identity_picker
      select_identity_source("Photo")
      attach_identity_picker_file(logo_fixture)

      wait_for_crop_view
      simulate_crop_adjustment

      click_button I18n.t("identity_picker.save_crop")

      wait_for_hub_view

      # Validates the Task H4 fix: JS sends avatar/avatar_original params
      # and the BrandingsController maps them to logo/logo_original
      workspace.reload
      expect(workspace.logo).to be_attached
      expect(workspace.logo_original).to be_attached
    end
  end

  describe "switch to initials" do
    before do
      workspace.logo.attach(
        io: File.open(logo_fixture),
        filename: "logo.png",
        content_type: "image/png"
      )
      workspace.logo_original.attach(
        io: File.open(logo_fixture),
        filename: "logo_original.png",
        content_type: "image/png"
      )
      workspace.save!
      visit edit_workspace_branding_path(workspace)  # refresh after attaching
    end

    it "switches workspace to Initials (no color picker for workspace) and purges logo" do
      open_identity_picker

      select_identity_source("Initials")

      # Workspace now has has_color_picker: true — color slider should be visible
      expect(page).to have_css("[data-identity-picker-target='colorSlider']", wait: 3)

      click_button I18n.t("identity_picker.save")

      # Modal closes
      expect(page).to have_no_css("dialog[open]", wait: 3)

      workspace.reload
      expect(workspace.logo).not_to be_attached
      expect(workspace.logo_original).not_to be_attached
    end
  end
end
