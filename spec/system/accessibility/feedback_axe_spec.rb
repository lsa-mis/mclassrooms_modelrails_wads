# frozen_string_literal: true

require "rails_helper"

# Proves the MiClassrooms-owned feedback form is axe-clean at AAA in both themes.
# We built this form in-house rather than mounting the lsa_tdx_feedback gem's
# self-contained modal (own CSS/JS, its own contrast/target sizing), which
# predates our WCAG 2.2 AAA + strict-CSP gates — so this spec is the proof that
# the in-house surface clears the bar the gem's modal wouldn't.
#
# Per-spec axe runs AA locally; the AAA 7:1 audit is the CI-only wcag2aaa hook
# (see spec/support/playwright_accessibility.rb). CI is the gate.
RSpec.describe "Feedback form — AAA", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:workspace) { create(:workspace, slug: "feedback-axe-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
    user = create(:user) # auto-joins the shared workspace via onboarding
    sign_in_via_form(user)
  end

  it "the empty feedback form is axe-clean at AAA (both themes)" do
    visit new_feedback_path

    expect(page).to have_content(I18n.t("feedback.new.title"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on feedback form: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "the validation-error state is axe-clean at AAA (both themes)" do
    visit new_feedback_path
    # Whitespace passes the HTML5 `required` attr but fails the server-side
    # presence validation, so the error state actually renders.
    fill_in I18n.t("feedback.form.message_label"), with: "   "
    click_button I18n.t("feedback.form.submit")

    expect(page).to have_content(I18n.t("feedback.errors.blank_message"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on feedback error state: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
