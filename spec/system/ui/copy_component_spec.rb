# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the copy component (the gem's browser lane runs
# with no compiled CSS and disables color-contrast; this is the 0b row). Scoped to the
# component so the preview-host chrome's own advisories don't count.
RSpec.describe "Copy component accessibility", type: :system do
  %w[default long_value label_hidden two_on_one_page].each do |scenario|
    it "#{scenario} passes AAA in both themes at rest" do
      visit "/rails/view_components/ui/copy_component/#{scenario}"
      expect(page).to have_css("[data-controller='copy']")
      # The check glyph is hidden only by the stylesheet's [hidden] rule (preflight);
      # this proves it against the real compiled CSS, which the gem's lanes cannot.
      expect(page).to have_no_css("svg[data-copy-target='successIcon']")
      expect(page).to have_css("svg[data-copy-target='copyIcon']")

      scope = [ "[data-controller='copy']" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end

  it "default passes AAA in both themes in the copied and failed states" do
    visit "/rails/view_components/ui/copy_component/default"
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "clipboard", {
        value: { writeText: () => Promise.resolve() }, configurable: true
      })
    JS
    find("button[data-action='copy#copy']").click
    expect(page).to have_css("[data-controller='copy'][data-state='copied']")
    scope = [ "[data-controller='copy']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to be(true), axe_violations_in_both_themes(include: scope).join("\n")

    page.execute_script(%(Object.defineProperty(navigator, "clipboard", { value: undefined, configurable: true })))
    expect(page).to have_css("[data-controller='copy'][data-state='idle']", wait: 4)
    find("button[data-action='copy#copy']").click
    expect(page).to have_css("[data-controller='copy'][data-state='failed']")
    expect(axe_clean_in_both_themes?(include: scope)).to be(true), axe_violations_in_both_themes(include: scope).join("\n")
  end
end
