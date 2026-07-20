# frozen_string_literal: true

require "rails_helper"

# The gem's floating trigger is position:fixed bottom-right with z-index 9998,
# which paints it over our bottom-anchored chrome — toast cards (--toast-z: 100,
# bottom-center, near-full-width at phone size) most importantly. A persistent,
# low-priority button must not cover a transient error/warning toast (right where
# its dismiss button sits). lsa_tdx_feedback_overrides.css drops the trigger to
# just below --toast-z; this guards that relationship (computed, so the calc()
# and the token both resolve).
RSpec.describe "Feedback trigger stacking", type: :system do
  it "stacks the trigger below the toast layer" do
    visit about_path
    expect(page).to have_css("#lsa-tdx-feedback-trigger")

    z = page.evaluate_script(<<~JS)
      (() => {
        const trigger = getComputedStyle(
          document.getElementById('lsa-tdx-feedback-trigger')
        ).zIndex;
        const toast = getComputedStyle(document.documentElement)
          .getPropertyValue('--toast-z').trim();
        return { trigger: parseInt(trigger, 10), toast: parseInt(toast, 10) };
      })()
    JS

    expect(z["toast"]).to be > 0                 # token is defined
    expect(z["trigger"]).to be_between(1, z["toast"] - 1) # resolved, and below toasts
  end
end
