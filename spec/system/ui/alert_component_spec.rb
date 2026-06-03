# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the alert component.
#
# The destructive variant renders danger-colored text on `bg-surface-raised`.
# In DARK mode, surface-raised is the LIGHTEST dark surface (neutral-800), where
# danger-text contrast is lowest. This spec audits each scenario UNSCOPED on the
# alert (no color-contrast exclude) so it genuinely proves the dark
# `--color-danger` token now clears AAA 7:1 on the lightest dark surface — not
# that we excluded the failing element.
#
# The preview-host minimal layout emits axe best-practice advisories
# (landmark-one-main, page-has-heading-one) that are NOT WCAG and NOT about the
# alert. We scope the audit to the alert subtree by its live-region role so we
# audit the COMPONENT, not the host chrome. No color-contrast exclude is added:
# if a real contrast violation remained on the alert, this spec would fail and
# the token would not be fixed yet.
RSpec.describe "Alert component accessibility", type: :system do
  {
    "default"     => "status",
    "destructive" => "alert",
    "with_slots"  => "alert"
  }.each do |scenario, role|
    it "#{scenario} has role=#{role} and passes AAA in both themes" do
      visit "/rails/view_components/ui/alert_component/#{scenario}"

      expect(page).to have_css("[role='#{role}']")

      # Scope to the alert subtree (its live-region role), NOT the host chrome.
      # No color-contrast exclude — a real contrast failure on the alert would
      # still fail this spec.
      scope = [ "[role='#{role}']" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
