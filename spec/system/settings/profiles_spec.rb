require "rails_helper"

RSpec.describe "Account profile — identity picker", type: :system do
  let(:user) { create(:user) }
  let(:avatar_fixture) { Rails.root.join("spec/fixtures/files/avatar.png") }

  before do
    sign_in_via_form(user)
    visit edit_settings_profile_path
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

      # Color picker panel should appear (server-rendered when initials selected)
      expect(page).to have_css("[data-identity-picker-target='colorSlider']", wait: 3)

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
        visit edit_settings_profile_path
      end

      it "switches to Gravatar" do
        open_identity_picker

        select_identity_source("Gravatar")

        # No color picker for Gravatar (panel is not rendered server-side)
        expect(page).to have_no_css("[data-identity-picker-target='colorSlider']", wait: 2)

        click_button I18n.t("identity_picker.save")

        # Modal closes on save & apply
        expect(page).to have_no_css("dialog[open]", wait: 3)

        user.reload
        expect(user.avatar_source).to eq("gravatar")
      end
    end
  end

  describe "re-crop existing photo" do
    let(:user) { create_user_with_avatar }

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
    let(:user) { create_user_with_avatar }

    it "persists removal immediately (without clicking Save & apply)" do
      open_identity_picker

      # Enter crop view via photo preview
      find("button[data-identity-picker-target='photoPreview']").click
      wait_for_crop_view

      click_button I18n.t("identity_picker.remove_photo")

      # Remove photo submits a DELETE via button_to and the turbo stream
      # response closes the modal automatically
      expect(page).to have_no_css("dialog[open]", wait: 5)

      # Server state persisted immediately — no Save & apply needed
      user.reload
      expect(user.avatar).not_to be_attached
      expect(user.avatar_original).not_to be_attached
      expect(user.avatar_source).to eq("initials")
    end
  end

  describe "navigation from crop view" do
    let(:user) { create_user_with_avatar }

    it "Escape returns to hub without closing the modal" do
      open_identity_picker
      find("button[data-identity-picker-target='photoPreview']").click
      wait_for_crop_view

      cdp_press("Escape")

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
    let(:user) { create_user_with_avatar }

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
    it "navigates to Initials source via Tab and Enter and shows color picker" do
      open_identity_picker

      # Source cards are now links. Tab to the Initials link and press Enter.
      # For a default user (no Gravatar), available sources are ["upload", "initials"].
      # We Tab past the Photo link to reach Initials, then activate it.
      # Focus the first source card link (Photo)
      cdp_execute(<<~JS)
        const firstLink = document.querySelector(
          "#identity-picker-hub [role='radiogroup'] a[role='radio']"
        )
        firstLink.focus()
      JS
      # Tab to the next source card (Initials)
      cdp_press("Tab")
      # Activate the Initials link
      cdp_press("Enter")

      # Wait for turbo frame to reload with Initials selected
      expect(page).to have_css("#identity-picker-hub", wait: 5)

      # Initials preview now visible (server-rendered for the initials source)
      expect(page).to have_css("[data-identity-picker-target='initialsPreview']", wait: 3)

      # Color slider visible (has_color_picker: true for User)
      expect(page).to have_css("[data-identity-picker-target='colorSlider']")

      # The Initials source card has the selected-state aria attribute
      expect(page).to have_css("#identity-picker-hub a[aria-checked='true']",
        text: I18n.t("identity_picker.sources.initials.title"))

      # Close the modal before the after(:each) axe audit runs.
      cdp_press("Escape")
      expect(page).to have_no_css("dialog[open]", wait: 3)
    end
  end

  describe "file picker dismissal" do
    # Regression guard for a bug caught during characterization testing:
    # when openFilePicker() calls fileInputTarget.click() inside a <dialog>
    # and the user dismisses the OS file dialog (Escape on native picker),
    # the browser fires a cancel event on the ancestor <dialog>. The modal
    # controller's cancel handler would previously close the whole modal.
    # The fix: identity_picker_controller sets a _filePickerOpen flag while
    # the picker is open, and its cancel handler suppresses the close event
    # (preventDefault + stopImmediatePropagation) so the user returns to hub.
    it "keeps the modal open on hub when a cancel event fires during file picker" do
      # Force a fast modal close animation so the dialog[open] assertion below
      # reliably reflects "this didn't close" rather than "this hasn't finished
      # closing yet". Without the fix, the modal controller calls close() which
      # animates out before setting dialog.open = false.
      page.execute_script(
        "document.documentElement.style.setProperty('--modal-animation-duration', '50ms')"
      )

      open_identity_picker

      # Simulate the state right after openFilePicker() has been called:
      # flag is true, then a cancel event arrives on the dialog (as the browser
      # fires when the OS file dialog is dismissed without a selection).
      page.execute_script(<<~JS)
        const el = document.querySelector("[data-controller~='identity-picker']")
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "identity-picker")
        ctrl._filePickerOpen = true

        const dialog = document.querySelector("dialog[open]")
        dialog.dispatchEvent(new Event("cancel", { bubbles: false, cancelable: true }))
      JS

      # Wait longer than the modal animation; if the fix regressed, the dialog
      # would have finished closing by now.
      sleep 0.2

      # Modal remains open, hub view still visible
      expect(page).to have_css("dialog[open]")
      expect(page).to have_css("#identity-picker-hub:not([hidden])")

      # Flag was reset by the cancel handler
      flag_cleared = page.evaluate_script(<<~JS)
        (() => {
          const el = document.querySelector("[data-controller~='identity-picker']")
          const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "identity-picker")
          return ctrl._filePickerOpen === false
        })()
      JS
      expect(flag_cleared).to eq(true)

      # Close the modal before the after(:each) axe audit runs.
      # The hub's initials source card uses oklch() with a CSS custom property
      # that axe-core can't resolve for contrast computation.
      cdp_press("Escape")
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

      cdp_intercept(%r{/settings/avatar}) do |request|
        if request.method == "PATCH"
          patch_count += 1
          sleep 1 # keeps the first request in flight long enough for a second click
        end
        request.continue
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
