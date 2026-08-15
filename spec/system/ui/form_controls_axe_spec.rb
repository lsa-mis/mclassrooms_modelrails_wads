# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the just-vendored form controls
# (checkbox, select, radio_group, toggle). Mirrors the proven
# `alert_component_spec.rb` pattern: visit the ViewComponent preview-host URL for
# a representative scenario, assert the control's element/role is present, then
# run axe at AAA in BOTH themes scoped to the component subtree.
#
# Why scope to the subtree (via `include:`): the preview-host minimal layout
# emits axe `best-practice` advisories (landmark-one-main, page-has-heading-one)
# that are NOT WCAG and NOT about the control. Scoping to the component keeps
# those host-chrome advisories out of scope WITHOUT excluding any rule. No
# color-contrast exclude is added anywhere here — a real contrast failure on a
# control would still fail this spec.
#
# The `invalid` scenario is audited for checkbox/select/radio_group: it sets
# `aria-invalid` and renders the danger-colored error message, so it is the
# state most likely to surface an AAA contrast regression (the `.text-danger`
# token on `bg-surface-raised` in dark mode). Auditing it proves invalid-state AAA.
RSpec.describe "Form control accessibility", type: :system do
  # `let` (read inside the audit def) / locals (drive class-level example
  # generation) — bare constants land on Object and collide across parallel
  # workers (#607/#608).
  let(:preview_host) { "/rails/view_components" }

  # component => { scenario => selector that proves the control/role rendered }
  representative = {
    "checkbox_component"    => { "default" => "input[type='checkbox']" },
    "select_component"      => { "default" => "select" },
    "radio_group_component" => { "default" => "[role='radiogroup']" },
    "toggle_component"      => { "default" => "button[aria-pressed]" }
  }.freeze

  # The invalid state for the input-bearing controls: proves the aria-invalid +
  # danger error-message combination clears AAA in both themes.
  invalid_scenarios = {
    "checkbox_component"    => "input[type='checkbox'][aria-invalid='true']",
    "select_component"      => "select[aria-invalid='true']",
    "radio_group_component" => "[role='radiogroup'][aria-invalid='true']"
  }.freeze

  def audit(component, scenario, selector)
    visit "#{preview_host}/ui/#{component}/#{scenario}"
    expect(page).to have_css(selector)

    # Scope the audit to the control's subtree, NOT the host chrome. No
    # color-contrast exclude — a real contrast failure here would still fail.
    scope = [ selector ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  representative.each do |component, scenarios|
    scenarios.each do |scenario, selector|
      it "#{component} #{scenario} renders #{selector} and passes AAA in both themes" do
        audit(component, scenario, selector)
      end
    end
  end

  invalid_scenarios.each do |component, selector|
    it "#{component} invalid renders #{selector} and passes AAA in both themes" do
      audit(component, "invalid", selector)
    end
  end

  # BONUS: prove the toggle's Stimulus controller actually flips aria-pressed in
  # a real browser (false -> true on click). The render harness only checks the
  # initial attribute; this proves the click->toggle#toggle wiring works.
  it "toggle flips aria-pressed false -> true on click" do
    visit "#{preview_host}/ui/toggle_component/default"

    button = find("button[aria-pressed]")
    expect(button["aria-pressed"]).to eq("false")

    button.click

    # Capybara waits/retries on this matcher until the Stimulus action runs.
    expect(page).to have_css("button[aria-pressed='true']")
    expect(find("button[aria-pressed]")["data-state"]).to eq("on")
  end
end
