# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the video component.
#
# The native <video> element renders the browser's own (keyboard-operable,
# UA-labelled) controls; the `captions` scenario also proves a
# <track kind="captions"> reaches the DOM. The per-spec axe call runs the
# default (AA) rule set; the authoritative AAA 7:1 audit is the CI-only
# wcag2aaa after-hook (spec/support/axe_accessibility.rb).
RSpec.describe "Video component accessibility", type: :system do
  let(:scope) { [ "[data-test='video']" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "default: native video controls pass AAA in both themes" do
    visit "/rails/view_components/ui/video_component/default"

    expect(page).to have_css("video", visible: :all)
    expect_aaa_in_both_themes
  end

  it "captions: a captions track is present and AAA passes in both themes" do
    visit "/rails/view_components/ui/video_component/captions"

    expect(page).to have_css("video", visible: :all)
    expect(page).to have_css("video track[kind='captions']", visible: :all)
    expect_aaa_in_both_themes
  end
end
