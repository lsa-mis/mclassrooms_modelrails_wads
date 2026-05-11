# frozen_string_literal: true

# Shared helpers for identity picker system specs (user avatar + workspace logo).
# Tests hit the real rendered pages. Cropper.js gestures are simulated via the
# controller's JS API rather than synthetic pointer events (flakier and slower).
module IdentityPickerHelpers
  # Sign in a user via the real login form (fills email, continues, fills password, submits).
  # Works in system specs where the session cookie must live in the Playwright browser,
  # not the Rack::Test cookie jar.
  def sign_in_via_form(user, password: "SecureP@ssw0rd123!")
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: password
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
  end

  # Open the identity picker modal from a profile or branding edit page.
  # Both pages place the trigger inside a [data-controller="modal"] container.
  # The hub is loaded via a lazy turbo frame, so we wait for content to appear.
  # 10s budget — same as wait_for_crop_view/hub_view — to match observed CI
  # runner contention rather than ideal-conditions timing.
  def open_identity_picker
    find("[data-controller='modal'] button[data-action*='modal#open']", match: :first).click
    expect(page).to have_css("dialog[open]", wait: 10)
    # Wait for the hub turbo frame to load its content
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
    # Wait for the turbo frame to finish loading (Turbo removes [busy] when done)
    expect(page).to have_no_css("#identity-picker-hub[busy]", wait: 10)
    # Wait for the selected source to be active
    expect(page).to have_css(
      "#identity-picker-hub a[aria-checked='true']", text: title, wait: 10
    )
  end

  # Attach a file to the identity picker's hidden file input.
  # The input has the sr-only class, so Capybara must be told visible: false.
  def attach_identity_picker_file(path)
    input = page.find("input[data-identity-picker-target='fileInput']", visible: false)
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
      const slider = document.querySelector("[data-identity-picker-target='colorSlider']")
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
  end

  # Wait for hub view to become visible (after a mode switch back to hub).
  # 10s budget matches wait_for_crop_view — under CI runner contention the
  # exit-crop → unhide-hub round trip has been observed to exceed 5s and
  # flake the subsequent title assertion (which is synchronous with the
  # unhide, so the wait IS what budgets it).
  def wait_for_hub_view
    expect(page).to have_css("#identity-picker-hub:not([hidden])", wait: 10)
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
