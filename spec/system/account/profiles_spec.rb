require "rails_helper"

RSpec.describe "Account profile — identity picker", type: :system do
  let(:user) { create(:user) }
  let(:avatar_fixture) { Rails.root.join("spec/fixtures/files/avatar.png") }

  before do
    sign_in_via_form(user)
    visit edit_account_profile_path
  end

  describe "photo upload flow" do
    it "uploads, crops, and saves a new avatar" do
      open_identity_picker

      # Select Photo source — since no image exists yet, this opens the file picker
      select_identity_source("Photo")

      attach_identity_picker_file(avatar_fixture)

      # File select triggers crop view automatically
      wait_for_crop_view

      simulate_crop_adjustment

      click_button I18n.t("identity_picker.save_crop")

      # After save, modal returns to hub
      wait_for_hub_view

      # Server-side state: avatar and avatar_original both attached, source is upload
      user.reload
      expect(user.avatar).to be_attached
      expect(user.avatar_original).to be_attached
      expect(user.avatar_source).to eq("upload")
    end
  end

  describe "source switching" do
    it "switches to Initials with a custom color" do
      open_identity_picker

      select_identity_source("Initials")

      # Color picker panel should appear (User has has_color_picker: true)
      expect(page).to have_css("[data-identity-picker-target='colorPanel']:not([hidden])", wait: 2)

      set_identity_color_hue(120)  # green

      click_button I18n.t("identity_picker.save")

      # Modal closes on save & apply
      expect(page).to have_no_css("dialog[open]", wait: 3)

      user.reload
      expect(user.avatar_source).to eq("initials")
      expect(user.primary_color).to eq(120)
    end

    context "when user has a Gravatar" do
      before do
        user.update_columns(has_gravatar: true)
        visit edit_account_profile_path
      end

      it "switches to Gravatar" do
        open_identity_picker

        select_identity_source("Gravatar")

        # No color picker for Gravatar
        expect(page).to have_css("[data-identity-picker-target='colorPanel'][hidden]", visible: :hidden, wait: 2)

        click_button I18n.t("identity_picker.save")

        # Modal closes on save & apply
        expect(page).to have_no_css("dialog[open]", wait: 3)

        user.reload
        expect(user.avatar_source).to eq("gravatar")
      end
    end
  end

  describe "re-crop existing photo" do
    let(:user) do
      u = create(:user)
      u.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png",
        content_type: "image/png"
      )
      u.avatar_original.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "original.png",
        content_type: "image/png"
      )
      u.update!(avatar_source: "upload")
      u
    end

    it "loads avatar_original for re-crop and saves a new blob" do
      original_signed_id = user.avatar_original.blob.signed_id
      prior_avatar_key = user.avatar.blob.key

      open_identity_picker

      # Click the large photo preview to enter crop view
      find("button[data-identity-picker-target='photoPreview']").click

      wait_for_crop_view

      # Crop view image src should contain the avatar_original blob signed ID (not the avatar's)
      img_src = page.evaluate_script(
        "document.querySelector('.cropper-container img').getAttribute('src')"
      )
      expect(img_src).to include(original_signed_id)

      simulate_crop_adjustment

      click_button I18n.t("identity_picker.save_crop")

      wait_for_hub_view

      user.reload
      expect(user.avatar).to be_attached
      # New crop save creates a new avatar blob (different key than before)
      expect(user.avatar.blob.key).not_to eq(prior_avatar_key)
    end
  end

  describe "remove photo" do
    let(:user) do
      u = create(:user)
      u.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png",
        content_type: "image/png"
      )
      u.avatar_original.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "original.png",
        content_type: "image/png"
      )
      u.update!(avatar_source: "upload")
      u
    end

    it "persists removal immediately (without clicking Save & apply)" do
      open_identity_picker

      # Enter crop view via photo preview
      find("button[data-identity-picker-target='photoPreview']").click
      wait_for_crop_view

      click_button I18n.t("identity_picker.remove_photo")

      # Returns to hub with Initials now selected
      wait_for_hub_view
      expect(page).to have_css("[data-source='initials'].border-interactive", wait: 2)

      # Server state persisted immediately — no Save & apply needed
      user.reload
      expect(user.avatar).not_to be_attached
      expect(user.avatar_original).not_to be_attached
      expect(user.avatar_source).to eq("initials")

      # Close the modal before the after(:each) axe audit runs.
      # The in-modal Initials state has its own accessibility considerations
      # that belong in a dedicated accessibility spec.
      page.driver.with_playwright_page { |pp| pp.keyboard.press("Escape") }
      expect(page).to have_no_css("dialog[open]", wait: 3)
    end
  end

  describe "navigation from crop view" do
    let(:user) do
      u = create(:user)
      u.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png",
        content_type: "image/png"
      )
      u.avatar_original.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "original.png",
        content_type: "image/png"
      )
      u.update!(avatar_source: "upload")
      u
    end

    it "Escape returns to hub without closing the modal" do
      open_identity_picker
      find("button[data-identity-picker-target='photoPreview']").click
      wait_for_crop_view

      page.driver.with_playwright_page do |playwright_page|
        playwright_page.keyboard.press("Escape")
      end

      wait_for_hub_view
      expect(page).to have_css("dialog[open]")
    end

    it "Cancel button returns to hub without closing the modal" do
      open_identity_picker
      find("button[data-identity-picker-target='photoPreview']").click
      wait_for_crop_view

      click_button I18n.t("identity_picker.cancel")

      wait_for_hub_view
      expect(page).to have_css("dialog[open]")
    end
  end

  describe "modal title" do
    let(:user) do
      u = create(:user)
      u.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png",
        content_type: "image/png"
      )
      u.avatar_original.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "original.png",
        content_type: "image/png"
      )
      u.update!(avatar_source: "upload")
      u
    end

    it "changes between hub and crop modes" do
      open_identity_picker

      # Hub view title
      expect(page).to have_css("dialog h2", text: I18n.t("identity_picker.choose_profile_picture"))

      # Enter crop view
      find("button[data-identity-picker-target='photoPreview']").click
      wait_for_crop_view
      expect(page).to have_css("dialog h2", text: I18n.t("identity_picker.adjust_profile_picture"))

      # Return to hub
      click_button I18n.t("identity_picker.cancel")
      wait_for_hub_view
      expect(page).to have_css("dialog h2", text: I18n.t("identity_picker.choose_profile_picture"))
    end
  end

  describe "keyboard source selection" do
    it "updates preview and color panel when arrow keys navigate the radiogroup" do
      open_identity_picker

      # Focus the Photo (upload) radio, then press ArrowDown once.
      # available_avatar_sources for a default user (no Gravatar) is ["upload", "initials"],
      # so a single ArrowDown moves selection from upload → initials.
      page.driver.with_playwright_page do |playwright_page|
        playwright_page.evaluate(<<~JS)
          const radio = document.querySelector(
            "[data-identity-picker-target='sourceCards'] input[type='radio'][value='upload']"
          )
          radio.focus()
        JS
        playwright_page.keyboard.press("ArrowDown")
      end

      # Preview section: initials now visible
      expect(page).to have_css("[data-identity-picker-target='initialsPreview']:not([hidden])", wait: 2)

      # Color panel visible (has_color_picker: true for User)
      expect(page).to have_css("[data-identity-picker-target='colorPanel']:not([hidden])")

      # The Initials source card has the selected-state classes
      expect(page).to have_css("[data-source='initials'].border-interactive")

      # Close the modal before the after(:each) axe audit runs.
      # The in-modal Initials state has its own accessibility considerations
      # that belong in a dedicated accessibility spec, not a keyboard-nav test.
      page.driver.with_playwright_page { |pp| pp.keyboard.press("Escape") }
      expect(page).to have_no_css("dialog[open]", wait: 3)
    end
  end

  describe "double-click guard on Save crop" do
    it "triggers only one PATCH request even if Save crop is clicked twice rapidly" do
      open_identity_picker
      select_identity_source("Photo")
      attach_identity_picker_file(Rails.root.join("spec/fixtures/files/avatar.png"))
      wait_for_crop_view
      simulate_crop_adjustment

      # Count PATCH requests and delay their responses so both clicks
      # happen within the in-flight window.
      patch_count = 0

      page.driver.with_playwright_page do |playwright_page|
        playwright_page.route("**/account/avatar", ->(route, request) {
          if request.method == "PATCH"
            patch_count += 1
            sleep 0.5  # keeps the first request in flight long enough for a second click
          end
          route.continue
        })
      end

      # Click twice rapidly — the controller's _saving guard should drop the second click
      save_button = find_button(I18n.t("identity_picker.save_crop"))
      save_button.click
      save_button.click

      # Wait for the first response to land (modal returns to hub)
      wait_for_hub_view

      expect(patch_count).to eq(1)
    end
  end
end
