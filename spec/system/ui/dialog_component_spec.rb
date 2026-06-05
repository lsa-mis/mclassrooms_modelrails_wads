# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility + behavior proof for the dialog (modal) component.
#
# This is the JS-BEHAVIOR pattern for the overlays family: the modal lives in the
# DOM but stays closed until its trigger fires, so we OPEN it via the real trigger
# and audit the LIVE modal — not the inert closed markup. We also prove the native
# Escape path closes it.
#
# NOTE: the per-spec axe call runs axe's default (AA) rule set; the authoritative
# AAA 7:1 audit is the CI-only wcag2aaa after-hook (spec/support/playwright_accessibility.rb).
RSpec.describe "Dialog component accessibility", type: :system do
  # The trigger carries `click->modal#open`. Clicking it runs showModal(), which
  # sets the `open` attribute synchronously.
  def open_modal
    find("[data-action~='click->modal#open']").click
    expect(page).to have_css("dialog[open]")
  end

  # Real-modal scenarios. `dont_no_title` is the teaching anti-pattern (no
  # aria-labelledby target) — not audited here.
  %w[basic with_form confirm_destructive].each do |scenario|
    it "#{scenario}: opens a modal that passes AAA in both themes" do
      visit "/rails/view_components/ui/dialog_component/#{scenario}"

      # Closed in the DOM until opened — full ARIA scaffolding present either way.
      expect(page).to have_css("dialog[role='dialog'][aria-modal='true']", visible: :all)

      open_modal

      # Audit the LIVE modal subtree (no color-contrast exclude).
      scope = [ "dialog[open]" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end

  it "closes on the native Escape (cancel) path" do
    visit "/rails/view_components/ui/dialog_component/basic"
    open_modal

    page.send_keys(:escape)

    expect(page).to have_no_css("dialog[open]")
  end
end
