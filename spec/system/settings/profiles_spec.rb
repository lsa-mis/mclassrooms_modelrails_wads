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
    # The gradient must live on the track pseudo-element, not the input. An inline
    # background on the input cannot reach the pseudo-element, so RangeComponent's
    # surface-sunken track painted a light 8px bar straight across the gradient
    # (W2-C regression — the view's old comment claimed inline wins "by design").
    it "paints the hue gradient on the slider track, not over it" do
      open_identity_picker
      select_identity_source("Initials")
      expect_color_picker_visible

      # getComputedStyle(el, "::-webkit-slider-runnable-track") cannot prove this:
      # Chrome resolves vendor pseudos in the two-arg form the same as a bogus one
      # (verified with a control probe — both fall back to the element's styles).
      # So assert the contract through the CSSOM instead: the SERVED stylesheet
      # carries the track-gradient rule, and the input wears the class + no inline
      # background for the rule to lose to.
      styles = page.evaluate_script(<<~JS)
        (() => {
          const el = document.querySelector("[data-identity-picker-target~='colorSlider']")
          // Chrome drops the ::-moz-range-track rule at parse (unknown selector) and
          // stores the var()-bearing declaration unparsed under the shorthand, so the
          // longhand backgroundImage getter returns "" — read cssText instead, and
          // expect exactly the engine-appropriate rule to survive.
          const trackRules = Array.from(document.styleSheets)
            .flatMap(s => { try { return Array.from(s.cssRules) } catch { return [] } })
            .filter(r => r.selectorText && r.selectorText.includes("hue-range") &&
                         r.selectorText.includes("track"))
          return {
            inline: el.getAttribute("style") || "",
            hasClass: el.classList.contains("hue-range"),
            gradientTrackRules: trackRules.filter(r => r.style.cssText.includes("linear-gradient")).length
          }
        })()
      JS

      expect(styles["inline"]).not_to include("linear-gradient")
      expect(styles["hasClass"]).to be(true)
      expect(styles["gradientTrackRules"]).to be >= 1 # the engine-appropriate rule
    end

    # Dragging the slider must preview by moving --hue, never by writing a literal
    # oklch() background — a hardcoded L/C is theme-blind, so in dark mode the live
    # preview showed the light-mode disc while save produced the re-lit one. Every
    # disc in the picker (big preview + the Initials card swatch) previews the
    # pending hue together, or they visibly disagree mid-drag.
    it "previews the pending hue on every picker disc, theme-aware" do
      open_identity_picker
      select_identity_source("Initials")
      expect_color_picker_visible

      set_identity_color_hue(120)

      state = page.evaluate_script(<<~JS)
        (() => {
          const preview = document.querySelector("[data-identity-picker-target~='initialsPreview']")
          const swatches = Array.from(document.querySelectorAll("[data-identity-picker-target~='hueSwatch']"))
          // hueSwatch now also rides the slider (its --hue feeds the loupe thumb);
          // computed-background sync is a property of the DISCS — the elements that
          // paint bg-hue-initials directly.
          const discs = [preview, ...swatches.filter(s => s !== preview && s.classList.contains("bg-hue-initials"))]
          return {
            swatchCount: swatches.length,
            inlineBg: preview.style.backgroundColor,
            previewHue: preview.style.getPropertyValue("--hue").trim(),
            distinctColors: new Set(discs.map(d => getComputedStyle(d).backgroundColor)).size
          }
        })()
      JS

      expect(state["inlineBg"]).to eq("") # no theme-blind override
      expect(state["previewHue"]).to eq("120")
      expect(state["swatchCount"]).to be >= 2 # big preview + card disc
      expect(state["distinctColors"]).to eq(1) # every disc shows the same pending color
    end

    # The thumb is a loupe: it shows the color the pending hue produces, using the
    # SAME oklch(var(--hue-initials-*)) formula as the discs, sized up from the
    # component's 20px. That needs --hue on the slider element itself (the slider
    # rides hueSwatchTargets), plus .hue-range thumb rules in the served sheet.
    it "fills the slider thumb with the pending color, loupe-style" do
      open_identity_picker
      select_identity_source("Initials")
      expect_color_picker_visible

      set_identity_color_hue(120)

      state = page.evaluate_script(<<~JS)
        (() => {
          const slider = document.querySelector("[data-identity-picker-target~='colorSlider']")
          const thumbRules = Array.from(document.styleSheets)
            .flatMap(s => { try { return Array.from(s.cssRules) } catch { return [] } })
            .filter(r => r.selectorText && r.selectorText.includes("hue-range") &&
                         r.selectorText.includes("thumb"))
          return {
            sliderHue: slider.style.getPropertyValue("--hue").trim(),
            loupeRules: thumbRules.filter(r => r.style.cssText.includes("--hue-initials-l")).length
          }
        })()
      JS

      expect(state["sliderHue"]).to eq("120") # the thumb's color input moves with the drag
      expect(state["loupeRules"]).to be >= 1  # engine-appropriate thumb rule, token-based fill
    end

    it "switches to Initials with a custom color" do
      open_identity_picker
      select_identity_source("Initials")
      expect_color_picker_visible

      set_identity_color_hue(120)
      save_and_apply

      expect_avatar_source(user, :initials)
      expect(user.primary_color).to eq(120)
    end

    # Regression guard (#912): onHubLoad's `data-action` binding must live on
    # the persistent <turbo-frame> (_identity_picker.html.erb), not the hub
    # partial's own frame tag — a real navigation never copies the response
    # tag's own attributes onto the live element, so a binding declared
    # there silently never fires. select_identity_source is a real
    # turbo-frame navigation (not the crop round-trip, which calls
    # onHubLoad manually), so this only passes if onHubLoad actually runs
    # off that event.
    it "announces the newly selected source via the live region" do
      open_identity_picker
      select_identity_source("Initials")

      within("[data-controller~='identity-picker']") do
        expect(page).to have_css("[aria-live='polite']", text: I18n.t("identity_picker.sources.initials.title"), visible: :all)
      end
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

      expect(page).to have_css("[data-identity-picker-target~='initialsPreview']", wait: 3)
      expect_color_picker_visible
      expect(page).to have_css("#identity-picker-hub a[aria-checked='true']",
        text: I18n.t("identity_picker.sources.initials.title"))
    end
  end

  describe "file picker dismissal" do
    # Regression guard for a bug caught during characterization testing:
    # activating the "Upload new" label forwards a click to its file input
    # inside a <dialog>, and when the user dismisses the OS file dialog
    # (Escape on native picker), the browser fires a cancel event on the
    # ancestor <dialog>. The modal controller's cancel handler would
    # previously close the whole modal. The fix: identity_picker_controller
    # sets a _filePickerOpen flag while the picker is open, and its cancel
    # handler suppresses the close event (preventDefault +
    # stopImmediatePropagation) so the user returns to hub.
    it "keeps the modal open on hub when a cancel event fires during file picker" do
      # Force a fast modal close animation so the dialog[open] assertion below
      # reliably reflects "this didn't close" rather than "this hasn't finished
      # closing yet". Without the fix, the modal controller calls close() which
      # animates out before setting dialog.open = false.
      page.execute_script(
        "document.documentElement.style.setProperty('--modal-animation-duration', '50ms')"
      )

      open_identity_picker

      # Simulate the state right after the "Upload new" label's forwarded
      # click has armed the flag: flag is true, then a cancel event arrives
      # on the dialog (as the browser fires when the OS file dialog is
      # dismissed without a selection).
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

  describe "keyboard access to the upload trigger" do
    # The file input is a DOM sibling immediately after its label (#912 —
    # focus order matches visual order), so Tab reaches it right after the
    # crop footer's own buttons, and the ring paints on that label
    # (application.css). This proves both the order and the paint.
    it "reaches the crop input right after the crop footer buttons, with the focus ring on its label" do
      open_identity_picker
      upload_photo(avatar_fixture)

      input_id = "#{ActionView::RecordIdentifier.dom_id(user)}-identity-picker-file-crop"
      label_outline = lambda do
        page.evaluate_script(<<~JS)
          (() => {
            const input = document.getElementById("#{input_id}");
            const label = input && input.previousElementSibling;
            return label ? getComputedStyle(label).outlineStyle : "no label";
          })()
        JS
      end
      expect(label_outline.call).to eq("none")

      reached = false
      previous_focus_tag = nil
      previous_focus_text = nil
      20.times do
        previous_focus_tag = page.evaluate_script("document.activeElement.tagName")
        previous_focus_text = page.evaluate_script("document.activeElement.textContent.trim()")
        cdp_press("Tab")
        if page.evaluate_script("document.activeElement.id") == input_id
          reached = true
          break
        end
      end
      expect(reached).to be(true), "Tab never reached the crop file input"
      # The label isn't tabbable (native labels aren't in the tab order), so
      # the stop right before the input is the last focusable element ahead
      # of it — the crop footer's own "Save crop" button.
      expect(previous_focus_tag).to eq("BUTTON")
      expect(previous_focus_text).to eq(I18n.t("identity_picker.save_crop"))
      # Bounded poll for the paint, not a read-once. The flake #997 saw here
      # was not paint lag: the picker's deferred focus move was landing after
      # the Tab and taking focus back, which wait_for_crop_view now waits out.
      Timeout.timeout(Capybara.default_max_wait_time) do
        sleep 0.05 until label_outline.call == "solid"
      end
      expect(label_outline.call).to eq("solid")
    end
  end
end
