# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the five Wave-2 form controls that have no
# Stimulus behavior (label, search_input, number_input, range, floating_label).
# The rating_input — which DOES carry hover/select behavior and a graphic-contrast
# concern — gets its own enhanced spec (rating_input_component_spec.rb).
#
# For each control we visit a representative scenario, assert the real element
# rendered, and run axe AAA in BOTH themes scoped to the component subtree (via
# `include:`) — NO color-contrast exclude. A real contrast/role failure on the
# control would fail this spec; we audit the COMPONENT, not the preview-host
# chrome (whose minimal layout emits non-WCAG best-practice advisories like
# landmark-one-main / page-has-heading-one).
#
# The `invalid` scenarios for the three controls that have an error axis
# (search_input, number_input, floating_label) are audited too, so the
# aria-invalid error border/ring tokens are proven at AAA as well.
RSpec.describe "Wave-2 form controls accessibility", type: :system do
  FORMS_PREVIEW_ROOT = "/rails/view_components/ui"

  # component => { url: representative scenario path, selector: the real element }
  # The selector both proves the control rendered AND scopes the axe audit.
  {
    "label" => {
      url:      "label_component/for_an_input",
      selector: "label"
    },
    "search_input" => {
      url:      "search_input_component/default",
      selector: "input[type='search']"
    },
    "number_input" => {
      url:      "number_input_component/default",
      selector: "input[type='number']"
    },
    "range" => {
      url:      "range_component/default",
      selector: "input[type='range']"
    },
    "floating_label" => {
      url:      "floating_label_component/default",
      selector: "input.peer"
    }
  }.each do |component, spec|
    it "#{component} renders and passes AAA in both themes" do
      visit "#{FORMS_PREVIEW_ROOT}/#{spec[:url]}"

      expect(page).to have_css(spec[:selector])

      scope = [ spec[:selector] ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end

  # Invalid-state AAA: the aria-invalid error border + ring tokens must still
  # clear 7:1 / 3:1 in both themes. Scoped to the control; no contrast exclude.
  {
    "search_input"   => "input[type='search']",
    "number_input"   => "input[type='number']",
    "floating_label" => "input.peer"
  }.each do |component, selector|
    it "#{component} invalid scenario passes AAA in both themes" do
      visit "#{FORMS_PREVIEW_ROOT}/#{component}_component/invalid"

      expect(page).to have_css("#{selector}[aria-invalid='true']")

      scope = [ selector ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
