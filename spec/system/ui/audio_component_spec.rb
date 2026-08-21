# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the audio component.
#
# The native <audio> element renders the browser's own (keyboard-operable,
# UA-labelled) controls, so the 0b only proves the element is present and the
# surrounding chrome clears AAA in both themes. The per-spec axe call runs the
# default (AA) rule set; the authoritative AAA 7:1 audit is the CI-only
# wcag2aaa after-hook (spec/support/axe_accessibility.rb).
RSpec.describe "Audio component accessibility", type: :system do
  # `let`, not a top-level constant (a constant inside describe leaks to ::SCOPE
  # and collides across scoped 0b specs).
  let(:scope) { [ "[data-test='audio']" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "default: native audio controls pass AAA in both themes" do
    visit "/rails/view_components/ui/audio_component/default"

    expect(page).to have_css("audio", visible: :all)
    expect_aaa_in_both_themes
  end

  it "multi_source: multiple sources pass AAA in both themes" do
    visit "/rails/view_components/ui/audio_component/multi_source"

    expect(page).to have_css("audio", visible: :all)
    expect_aaa_in_both_themes
  end
end
