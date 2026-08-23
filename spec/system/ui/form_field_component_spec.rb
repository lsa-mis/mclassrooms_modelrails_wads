# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the repaired FormFieldComponent (B1).
#
# The component's whole job is the wiring the broken version dropped: a
# `<label for>` bound to the control, hint/error paragraphs with real ids that the
# control references via `aria-describedby`, and `aria-invalid` on error. These
# specs assert that wiring on the REAL rendered preview (not the unit harness), then
# audit AAA contrast on the field subtree.
#
# Each preview wraps the field in `#field-scope` so axe audits the COMPONENT, not the
# host chrome (the minimal preview layout yields the field next to a dev theme
# toggle). No color-contrast exclude — a real contrast failure on the field's text
# (label / hint / error / input) would still fail this spec.
RSpec.describe "FormField component accessibility", type: :system do
  # `let`, not a top-level constant (a constant inside describe leaks to ::SCOPE and
  # collides across scoped 0b specs → axe scopes to the wrong selector).
  let(:scope) { [ "#field-scope" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "default: binds the label to the control and passes AAA in both themes" do
    visit "/rails/view_components/ui/form_field_component/default"

    expect(page).to have_css("label[for='preview_email']", text: "Email")
    expect(page).to have_css("input#preview_email")
    expect_aaa_in_both_themes
  end

  it "with_hint: the control's aria-describedby references the hint id; AAA in both themes" do
    visit "/rails/view_components/ui/form_field_component/with_hint"

    expect(page).to have_css("p#preview_email-hint[data-slot='description']", text: "share")
    expect(page).to have_css("input#preview_email[aria-describedby~='preview_email-hint']")
    expect_aaa_in_both_themes
  end

  it "with_error: the control is aria-invalid and describedby the error id; AAA in both themes" do
    visit "/rails/view_components/ui/form_field_component/with_error"

    # Plain markup, not role=alert — a field-level live region never fires on a
    # server-rendered response. UI::ErrorSummaryComponent is the real, focused
    # announcement mechanism (see the class header on FormFieldComponent).
    expect(page).to have_css("p#preview_email-error[data-slot='description']")
    expect(page).to have_no_css("p#preview_email-error[role='alert']")
    expect(page).to have_css("input#preview_email[aria-invalid='true'][aria-describedby~='preview_email-error']")
    expect_aaa_in_both_themes
  end

  it "required: decorative marker on the label, required on the control; AAA in both themes" do
    visit "/rails/view_components/ui/form_field_component/required"

    expect(page).to have_css("label[for='preview_email'] span[aria-hidden='true']", text: "*")
    expect(page).to have_css("input#preview_email[required]")
    expect_aaa_in_both_themes
  end
end
