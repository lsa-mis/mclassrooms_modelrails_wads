# frozen_string_literal: true

# Shared helpers for identity picker system specs (user avatar + workspace logo).
# Tests hit the real rendered pages. Cropper.js gestures are simulated via the
# controller's JS API rather than synthetic pointer events (flakier and slower).
module IdentityPickerHelpers
  # Open the identity picker modal from a profile or branding edit page.
  # Both pages place the trigger inside a [data-controller="modal"] container.
  # The hub is loaded via a lazy turbo frame, so we wait for content to appear.
  # 10s budget — same as wait_for_crop_view/hub_view — to match observed CI
  # runner contention rather than ideal-conditions timing.
  def open_identity_picker
    find("[data-controller='modal'] button[data-action*='modal#open']", match: :first).click
    expect(page).to have_css("dialog[open]", wait: 10)
    expect(page).to have_css("#identity-picker-hub [role='radiogroup']", wait: 10)
  end

  # Click a source card by the visible title text ("Photo", "Gravatar", "Initials").
  # Source cards are now <a> links inside the turbo frame hub that reload it via GET.
  # Waits for the turbo frame to finish loading (no [busy] attribute) and confirm the
  # selected source is active.
  def select_identity_source(title)
    within("#identity-picker-hub") do
      click_link title
    end
    expect(page).to have_no_css("#identity-picker-hub[busy]", wait: 10)
    expect(page).to have_css(
      "#identity-picker-hub a[aria-checked='true']", text: title, wait: 10
    )
  end

  # Attach a file to the identity picker's hidden file input. Each view (hub,
  # crop) now has its own input, sr-only and a DOM sibling of its own label
  # (#912 — focus order), so both can match `[data-identity-picker-target=
  # 'fileInput']` at once (the crop one hidden behind [hidden] on its
  # ancestor). Callers always reach this from the hub (see upload_photo, the
  # only caller), so scope to it explicitly rather than leaving the match
  # ambiguous. Capybara must be told visible: false — sr-only isn't display:none.
  def attach_identity_picker_file(path)
    input = find("#identity-picker-hub input[data-identity-picker-target='fileInput']", visible: false)
    input.attach_file(path)
  end

  # Simulate a crop adjustment by calling Cropper.js v2 selection API via JS.
  # Moves the selection 10px right + 10px down. Does NOT use synthetic pointer events.
  def simulate_crop_adjustment
    page.execute_script(<<~JS)
      const cropperEl = document.querySelector("[data-controller='image-cropper']")
      const app = window.Stimulus
      const ctrl = app.getControllerForElementAndIdentifier(cropperEl, "image-cropper")
      const selection = ctrl._cropper.getCropperSelection()
      selection.$move(10, 10)
    JS
  end

  # Update the OKLCH hue slider value via JS and dispatch the input event
  # so the Stimulus controller re-renders the preview and updates the hidden field.
  def set_identity_color_hue(hue)
    page.execute_script(<<~JS)
      const slider = document.querySelector("[data-identity-picker-target~='colorSlider']")
      slider.value = #{hue}
      slider.dispatchEvent(new Event('input', { bubbles: true }))
    JS
  end

  # Wait for crop view to become visible AND the cropper to be fully ready.
  # Cropper.js v2's init path is async (dynamic `import("cropperjs")` + web
  # component mount + base transform capture + event listener registration);
  # under CI runner contention the chain has exceeded the previous 5s budget
  # and flaked across several specs. Two assertions:
  #
  #   1. `cropSection` is unhidden — confirms the mode switch completed.
  #   2. `data-image-cropper-ready="true"` is set — confirms
  #      `image_cropper_controller#_initCropper` reached the end of init
  #      (after `_initialized = true`, all listeners attached, slider reset).
  #      Cleared in `_destroy()` so re-inits have to re-publish — stale
  #      attribute can't satisfy this wait.
  #
  # 10s timeout is intentionally generous; CI's slowest observed init was
  # in the upload-then-crop path which adds a POST request to the budget.
  def wait_for_crop_view
    expect(page).to have_css(
      "[data-identity-picker-target='cropSection']:not([hidden])", wait: 10
    )
    expect(page).to have_css(
      "[data-controller~='image-cropper'][data-image-cropper-ready='true']",
      wait: 10
    )
    # The picker moves focus into the cropper container on a timer after the
    # modal animation (identity_picker_controller#_manageFocus). Until that has
    # landed the view is still settling: a spec that tabs before it fires has
    # its focus taken back (#997). Waiting on the focus is waiting on the state.
    expect(page).to have_css("[data-image-cropper-target='container']:focus", wait: 10)
  end

  # Wait for hub view to become visible (after a mode switch back to hub).
  # 10s budget matches wait_for_crop_view — under CI runner contention the
  # exit-crop → unhide-hub round trip has been observed to exceed 5s and
  # flake the subsequent title assertion (which is synchronous with the
  # unhide, so the wait IS what budgets it).
  def wait_for_hub_view
    expect(page).to have_css("#identity-picker-hub:not([hidden])", wait: 10)
  end

  # Choose the Photo source and attach a file. With no image selected yet the
  # source card opens the file picker, and a file selection enters crop view
  # automatically.
  def upload_photo(path)
    select_identity_source("Photo")
    attach_identity_picker_file(path)
    wait_for_crop_view
  end

  # Enter crop view from the hub by clicking the large photo preview
  # (rendered when a photo already exists).
  def enter_crop_view
    find("button[data-identity-picker-target='photoPreview']").click
    wait_for_crop_view
  end

  # The src of the image the cropper is editing in crop view.
  def crop_view_image_src
    page.evaluate_script(
      "document.querySelector('.cropper-container img').getAttribute('src')"
    )
  end

  # Save the crop; on success the modal returns to hub view.
  def save_crop_and_return_to_hub
    click_button I18n.t("identity_picker.save_crop")
    wait_for_hub_view
  end

  # Save & apply the selected source; the modal closes on success.
  def save_and_apply
    click_button I18n.t("identity_picker.save")
    expect(page).to have_no_css("dialog[open]", wait: 3)
  end

  # Remove photo submits a DELETE via button_to; the turbo stream response
  # closes the modal automatically (no Save & apply involved).
  def remove_photo_expecting_modal_close
    click_button I18n.t("identity_picker.remove_photo")
    expect(page).to have_no_css("dialog[open]", wait: 5)
  end

  # The color picker panel is server-rendered only for sources that support
  # it (initials); other sources omit it entirely.
  def expect_color_picker_visible
    expect(page).to have_css("[data-identity-picker-target~='colorSlider']", wait: 3)
  end

  def expect_no_color_picker
    expect(page).to have_no_css("[data-identity-picker-target~='colorSlider']", wait: 2)
  end

  # Reload the record and assert its persisted avatar source
  # ("upload", "gravatar", "initials").
  def expect_avatar_source(record, source)
    expect(record.reload.avatar_source).to eq(source.to_s)
  end

  def expect_returned_to_hub_without_closing_modal
    wait_for_hub_view
    expect(page).to have_css("dialog[open]")
  end

  # Focus the first source card link in the hub radiogroup, giving keyboard
  # navigation tests a deterministic starting position.
  def focus_first_source_card
    cdp_execute(<<~JS)
      const firstLink = document.querySelector(
        "#identity-picker-hub [role='radiogroup'] a[role='radio']"
      )
      firstLink.focus()
    JS
  end

  # Build a user with a cropped avatar and its original, source set to "upload".
  # Used by specs that start from the "user has an existing photo" state
  # (re-crop, remove, navigation, modal title, etc.).
  def create_user_with_avatar
    create(:user, :with_avatar)
  end
end

RSpec.configure do |config|
  config.include IdentityPickerHelpers, type: :system
end
