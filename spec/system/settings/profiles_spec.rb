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
      upload_photo(avatar_fixture)
      simulate_crop_adjustment
      save_crop_and_return_to_hub

      expect_avatar_source(user, :upload)
      expect(user.avatar).to be_attached
      expect(user.avatar_original).to be_attached
    end
  end

  describe "source switching" do
    it "switches to Initials with a custom color" do
      open_identity_picker
      select_identity_source("Initials")
      expect_color_picker_visible

      set_identity_color_hue(120)
      save_and_apply

      expect_avatar_source(user, :initials)
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
        expect_no_color_picker

        save_and_apply

        expect_avatar_source(user, :gravatar)
      end
    end
  end

  describe "re-crop existing photo" do
    let(:user) { create_user_with_avatar }

    it "loads avatar_original for re-crop and saves a new blob" do
      original_signed_id = user.avatar_original.blob.signed_id
      prior_avatar_key = user.avatar.blob.key

      open_identity_picker
      enter_crop_view
      expect(crop_view_image_src).to include(original_signed_id)

      simulate_crop_adjustment
      save_crop_and_return_to_hub

      user.reload
      expect(user.avatar).to be_attached
      expect(user.avatar.blob.key).not_to eq(prior_avatar_key)
    end
  end

  describe "remove photo" do
    let(:user) { create_user_with_avatar }

    it "persists removal immediately (without clicking Save & apply)" do
      open_identity_picker
      enter_crop_view

      remove_photo_expecting_modal_close

      expect_avatar_source(user, :initials)
      expect(user.avatar).not_to be_attached
      expect(user.avatar_original).not_to be_attached
    end
  end

  describe "navigation from crop view" do
    let(:user) { create_user_with_avatar }

    it "Escape returns to hub without closing the modal" do
      open_identity_picker
      enter_crop_view

      cdp_press("Escape")

      expect_returned_to_hub_without_closing_modal
    end

    it "Cancel button returns to hub without closing the modal" do
      open_identity_picker
      enter_crop_view

      click_button I18n.t("identity_picker.cancel")

      expect_returned_to_hub_without_closing_modal
    end
  end

  describe "modal title" do
    let(:user) { create_user_with_avatar }

    it "changes between hub and crop modes" do
      open_identity_picker
      expect(page).to have_css("dialog h2", text: I18n.t("identity_picker.choose_profile_picture"))

      enter_crop_view
      expect(page).to have_css("dialog h2", text: I18n.t("identity_picker.adjust_profile_picture"))

      click_button I18n.t("identity_picker.cancel")
      wait_for_hub_view
      expect(page).to have_css("dialog h2", text: I18n.t("identity_picker.choose_profile_picture"))
    end
  end

  describe "keyboard source selection" do
    it "navigates to Initials source via Tab and Enter and shows color picker" do
      open_identity_picker

      # For a default user (no Gravatar) the hub offers Photo then Initials,
      # so one Tab from the first source card lands on Initials.
      focus_first_source_card
      cdp_press("Tab")
      cdp_press("Enter")

      # Wait for the turbo frame to reload with Initials selected.
      expect(page).to have_css("#identity-picker-hub", wait: 5)

      expect(page).to have_css("[data-identity-picker-target='initialsPreview']", wait: 3)
      expect_color_picker_visible
      expect(page).to have_css("#identity-picker-hub a[aria-checked='true']",
        text: I18n.t("identity_picker.sources.initials.title"))

      close_modal_before_axe_audit
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

      # Condition-wait, not wall-clock (#453): a regressed cancel handler
      # closes the dialog via its close animation, so wait until the dialog
      # has NO running animations (settled state), then assert it stayed open.
      # On a loaded runner a fixed 0.2s could return mid-animation and
      # false-pass.
      settle_deadline = Time.current + 2
      sleep 0.05 until Time.current > settle_deadline ||
                       page.evaluate_script("(document.querySelector('dialog')?.getAnimations() || []).length").zero?

      expect(page).to have_css("dialog[open]")
      expect(page).to have_css("#identity-picker-hub:not([hidden])")

      flag_cleared = page.evaluate_script(<<~JS)
        (() => {
          const el = document.querySelector("[data-controller~='identity-picker']")
          const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "identity-picker")
          return ctrl._filePickerOpen === false
        })()
      JS
      expect(flag_cleared).to eq(true)

      close_modal_before_axe_audit
    end
  end

  describe "double-click guard on Save crop" do
    it "triggers only one PATCH request even if Save crop is clicked twice rapidly" do
      open_identity_picker
      upload_photo(avatar_fixture)
      simulate_crop_adjustment

      # Count PATCH requests and delay their responses so both clicks
      # happen within the in-flight window.
      patch_count = 0

      # Hold in-flight PATCHes until the double-click below has happened,
      # rather than a fixed 1s (#453): the hold releases the moment the second
      # click lands, and a slow runner can no longer outlive the window.
      double_click_done = false
      cdp_intercept(%r{/settings/avatar}) do |request|
        if request.method == "PATCH"
          patch_count += 1
          hold_deadline = Time.current + 5
          sleep 0.05 until double_click_done || Time.current > hold_deadline
        end
        request.continue
      end

      # Click twice rapidly — the controller's _saving guard should drop the second click
      save_button = find_button(I18n.t("identity_picker.save_crop"))
      save_button.click
      save_button.click
      double_click_done = true # release the held PATCH — the window has served its purpose

      wait_for_hub_view

      expect(patch_count).to eq(1)
    end
  end
end
