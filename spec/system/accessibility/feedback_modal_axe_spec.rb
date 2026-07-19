# frozen_string_literal: true

require "rails_helper"

# AAA regression guard for the adopted lsa_tdx_feedback modal (our view override
# at app/views/lsa_tdx_feedback/shared/_feedback_modal + the AAA retune in
# app/assets/stylesheets/lsa_tdx_feedback_overrides.css). The modal + trigger
# render site-wide from the layout tail; here we open the modal and audit the
# whole page, chrome included, in both themes — so the gem's Bootstrap colors
# (retuned to 7:1) and touch targets (retuned to 44px) can never regress unseen.
#
# Per-spec axe runs at the default rule level locally; AAA is the CI-only claim
# (see spec/support/playwright_accessibility.rb) — do not claim AAA from a local run.
RSpec.describe "Feedback modal — axe audit", type: :system do
  it "the opened feedback modal is axe-clean, chrome included (both themes)" do
    visit contact_path

    # Exercises the real open path: the /contact CTA -> feedback Stimulus
    # controller -> window.LsaTdxFeedback.showModal().
    click_button I18n.t("pages.contact.feedback.cta")
    expect(page).to have_css("#lsa-tdx-feedback-modal", visible: true)

    expect(axe_clean_in_both_themes?).to be(true),
      "violations with the feedback modal open: #{axe_violations_in_both_themes.join("\n")}"
  end
end
