# frozen_string_literal: true

# Preview-host accessibility + behavior proof for the alert_dialog (alertdialog)
# component.
#
# JS-BEHAVIOR pattern: the modal lives in the DOM but stays closed until its
# trigger fires. We OPEN it via the real trigger, audit the LIVE dialog, and
# prove the native Escape path closes it.
#
# NOTE: axe_clean_in_both_themes? runs axe DEFAULT (AA 4.5:1) locally. The
# authoritative AAA 7:1 audit is the CI-only wcag2aaa after-hook in
# spec/support/axe_accessibility.rb.
RSpec.describe "Alert Dialog component accessibility", type: :system do
  def open_alert_dialog
    find("[data-action~='click->modal#open']").click
    expect(page).to have_css("dialog[open]")
  end

  %w[basic confirm_destructive].each do |scenario|
    it "#{scenario}: opens an alertdialog that passes AAA in both themes" do
      visit "/rails/view_components/ui/alert_dialog_component/#{scenario}"

      # Closed in the DOM until opened — full ARIA scaffolding present either way.
      expect(page).to have_css("dialog[role='alertdialog'][aria-modal='true']", visible: :all)

      open_alert_dialog

      # The opened dialog must carry the alertdialog role (assertive announcement).
      expect(page).to have_css("dialog[role='alertdialog'][open]")

      # Audit the LIVE modal subtree.
      scope = [ "dialog[open]" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end

  it "closes on the native Escape (cancel) path" do
    visit "/rails/view_components/ui/alert_dialog_component/basic"
    open_alert_dialog

    page.send_keys(:escape)

    expect(page).to have_no_css("dialog[open]")
  end
end
